package com.microsoft.azure.refapp.backendlistener;

import com.microsoft.applicationinsights.TelemetryClient;
import com.microsoft.applicationinsights.internal.util.MapUtil;
import com.microsoft.applicationinsights.telemetry.Duration;
import com.microsoft.applicationinsights.telemetry.RequestTelemetry;

import org.apache.jmeter.config.Arguments;
import org.apache.jmeter.samplers.SampleResult;
import org.apache.jmeter.threads.JMeterContextService;
import org.apache.jmeter.visualizers.backend.AbstractBackendListenerClient;
import org.apache.jmeter.visualizers.backend.BackendListenerContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.regex.Matcher;

/**
 * Custom implementation of the JMeter Backend Listener client.
 * Dictates the metrics and telemetry captured and reported
 * to App Analytics by the JMeter (Azure Load Testing) client
 * of the Az Ref App.
 */
public class AzureBackendClient extends AbstractBackendListenerClient {

    /**
     * Logger.
     */
    private static final Logger log = LoggerFactory.getLogger(AzureBackendClient.class);

    /**
     * Argument keys.
     */
    private static final String KEY_TEST_NAME = "testName";
    private static final String KEY_SAMPLERS_LIST = "samplersList";
    private static final String KEY_USE_REGEX_FOR_SAMPLER_LIST = "useRegexForSamplerList";
    private static final String KEY_CUSTOM_PROPERTIES_PREFIX = "ai.";
    private static final String KEY_HEADERS_PREFIX = "aih.";
    private static final String KEY_RESPONSE_HEADERS = "responseHeaders";
    private static final String KEY_LOG_RESPONSE_DATA = "logResponseData";
    private static final String KEY_LOG_SAMPLE_DATA = "logSampleData";

    /**
     * Default values for the above arguments.
     */
    private static final String DEFAULT_TEST_NAME = "azrefapp";
    private static final String DEFAULT_SAMPLERS_LIST = "";
    private static final boolean DEFAULT_USE_REGEX_FOR_SAMPLER_LIST = false;
    private static final DataLoggingOption DEFAULT_LOG_RESPONSE_DATA = DataLoggingOption.ON_FAILURE;
    private static final DataLoggingOption DEFAULT_LOG_SAMPLE_DATA = DataLoggingOption.ON_FAILURE;

    /**
     * Separator for samplers list.
     */
    private static final String SEPARATOR = ";";

    /**
     * Truncated length of the request and response data.
     */
    private static final int MAX_DATA_LENGTH = 1024;

    /**
     * Application Insights telemetry client.
     */
    private TelemetryClient telemetryClient;

    /**
     * Name of the test.
     */
    private String testName;

    /**
     * Custom properties.
     */
    private final Map<String, String> customProperties;

    /**
     * Recording response headers.
     */
    private String[] responseHeaders;

    /**
     * List of samplers to record.
     */
    private String samplersList;

    /**
     * Regex if samplers are defined through regular expression.
     */
    private boolean useRegexForSamplerList;

    /**
     * Set of samplers to record.
     */
    private Set<String> samplersToFilter;

    /**
     * Whether to log the response data to the backend
     */
    private DataLoggingOption logResponseData;

    /**
     * Whether to log the sample data to the backend
     */
    private DataLoggingOption logSampleData;

    public AzureBackendClient() {
        super();
        this.samplersList = "";
        this.responseHeaders = new String[]{};
        this.customProperties = new HashMap<>();
    }

    /**
     * Constructs and returns a default set of parameters for a test configuration.
     * <p>
     * This method initializes an {@link Arguments} object with a predefined set of key-value pairs that represent
     * common configuration parameters used in a test run.
     * </p>
     *
     * @return An {@link Arguments} object containing the default test configuration parameters.
     */
    @Override
    public Arguments getDefaultParameters() {
        Arguments arguments = new Arguments();
        arguments.addArgument(KEY_TEST_NAME, DEFAULT_TEST_NAME);
        arguments.addArgument(KEY_SAMPLERS_LIST, DEFAULT_SAMPLERS_LIST);
        arguments.addArgument(KEY_USE_REGEX_FOR_SAMPLER_LIST, Boolean.toString(DEFAULT_USE_REGEX_FOR_SAMPLER_LIST));
        arguments.addArgument(KEY_LOG_RESPONSE_DATA, DEFAULT_LOG_RESPONSE_DATA.getValue());
        arguments.addArgument(KEY_LOG_SAMPLE_DATA, DEFAULT_LOG_SAMPLE_DATA.getValue());

        return arguments;
    }

    /**
     * Initializes the test configuration by extracting parameters from the provided {@link BackendListenerContext}.
     *
     * @param context The {@link BackendListenerContext} containing configuration parameters for the test.
     */
    @Override
    public void setupTest(BackendListenerContext context) {
        telemetryClient = new TelemetryClient();

        testName = context.getParameter(KEY_TEST_NAME, DEFAULT_TEST_NAME);
        samplersList = context.getParameter(KEY_SAMPLERS_LIST, DEFAULT_SAMPLERS_LIST).trim();
        useRegexForSamplerList = context.getBooleanParameter(KEY_USE_REGEX_FOR_SAMPLER_LIST,
                DEFAULT_USE_REGEX_FOR_SAMPLER_LIST);
        logResponseData = DataLoggingOption
                .fromString(context.getParameter(KEY_LOG_RESPONSE_DATA, DEFAULT_LOG_RESPONSE_DATA.getValue()));
        logSampleData = DataLoggingOption
                .fromString(context.getParameter(KEY_LOG_SAMPLE_DATA, DEFAULT_LOG_SAMPLE_DATA.getValue()));

        Iterator<String> iterator = context.getParameterNamesIterator();
        while (iterator.hasNext()) {
            String parameterName = iterator.next();

            if (parameterName.startsWith(KEY_CUSTOM_PROPERTIES_PREFIX)) {
                customProperties.put(parameterName, context.getParameter(parameterName));
            } else if (parameterName.equals(KEY_RESPONSE_HEADERS)) {
                responseHeaders = context.getParameter(KEY_RESPONSE_HEADERS).trim().toLowerCase()
                        .split("\\s*".concat(SEPARATOR).concat("\\s*"));
            } else {
                log.warn("Extraneous parameter provided '{}'. Ignoring.", parameterName);
            }
        }

        samplersToFilter = new HashSet<>();
        if (!useRegexForSamplerList) {
            String[] samplers = samplersList.split(SEPARATOR);

            samplersToFilter = new HashSet<>();
            samplersToFilter.addAll(Arrays.asList(samplers));
        }
    }

    /**
     * Tracks a request sample and captures the set of custom metrics & telemetry,
     * logging its data and response if applicable.
     *
     * @param name The name of the tracked request.
     * @param sr   The {@link SampleResult} containing the captured data of the request.
     */
    private void trackRequest(String name, SampleResult sr) {
        Map<String, String> properties = new HashMap<>(customProperties);
        properties.put("Bytes", Long.toString(sr.getBytesAsLong()));
        properties.put("SentBytes", Long.toString(sr.getSentBytes()));
        properties.put("ConnectTime", Long.toString(sr.getConnectTime()));
        properties.put("ErrorCount", Integer.toString(sr.getErrorCount()));
        properties.put("IdleTime", Double.toString(sr.getIdleTime()));
        properties.put("Latency", Double.toString(sr.getLatency()));
        properties.put("BodySize", Long.toString(sr.getBodySizeAsLong()));
        properties.put("TestStartTime", Long.toString(JMeterContextService.getTestStartTime()));
        properties.put("SampleStartTime", Long.toString(sr.getStartTime()));
        properties.put("SampleEndTime", Long.toString(sr.getEndTime()));
        properties.put("SampleLabel", sr.getSampleLabel());
        properties.put("ThreadName", sr.getThreadName());
        properties.put("URL", sr.getUrlAsString());
        properties.put("ResponseCode", sr.getResponseCode());
        properties.put("GrpThreads", Integer.toString(sr.getGroupThreads()));
        properties.put("AllThreads", Integer.toString(sr.getAllThreads()));
        properties.put("SampleCount", Integer.toString(sr.getSampleCount()));

        for (String header : responseHeaders) {
            Pattern pattern = Pattern.compile(String.format("^%s:(.*)$", header), Pattern.MULTILINE | Pattern.CASE_INSENSITIVE);
            Matcher matcher = pattern.matcher(sr.getResponseHeaders());

            if (matcher.find()) {
                properties.put(KEY_HEADERS_PREFIX.concat(header), matcher.group(1).trim());
            }
        }

        // Capture request data
        String samplerData = sr.getSamplerData();
        if (samplerData != null && logSampleData.shouldLog(sr.isSuccessful())) {
            if (sr.getDataType().equals(SampleResult.TEXT)) {
                if (samplerData.length() > MAX_DATA_LENGTH) {
                    log.warn("Sample data is too long, truncating it to {} characters", Optional.of(MAX_DATA_LENGTH));
                    samplerData = samplerData.substring(0, MAX_DATA_LENGTH) + "...[TRUNCATED]";
                }
            } else {
                log.warn("Sample data is in binary format, cannot log it");
                samplerData = "[BINARY DATA]";
            }

            properties.put("SampleData", samplerData);
        }

        String responseData = sr.getResponseDataAsString();
        if (responseData != null && logResponseData.shouldLog(sr.isSuccessful())) {
            if (sr.getDataType().equals(SampleResult.TEXT)) {
                if (responseData.length() > MAX_DATA_LENGTH) {
                    log.warn("Response data is too long, truncating it to {} characters", Optional.of(MAX_DATA_LENGTH));
                    responseData = responseData.substring(0, MAX_DATA_LENGTH) + "...[TRUNCATED]";
                }
            } else {
                log.warn("Response data is in binary format, cannot log it");
                responseData = "[BINARY DATA]";
            }

            properties.put("ResponseData", responseData);
        }

        // Build & send telemetry request
        Date timestamp = new Date(sr.getTimeStamp());
        Duration duration = new Duration(sr.getTime());
        RequestTelemetry req = new RequestTelemetry(name, timestamp, duration, sr.getResponseCode(), sr.isSuccessful());

        req.getContext().getOperation().setName(name);
        if (sr.getURL() != null) {
            req.setUrl(sr.getURL());
        }
        MapUtil.copy(properties, req.getProperties());

        telemetryClient.trackRequest(req);
    }

    /**
     * Processes a batch of sample results, tracking requests that match specified criteria.
     * <p>
     * The filtering criteria are:
     * </p>
     * <ul>
     * <li>If the samplers list is empty, all sample results are processed.</li>
     * <li>If regex is used for the sampler list, any sample label matching the regex is processed.</li>
     * <li>If regex is not used, process any sample label contained in the "samplers to filter" set.</li>
     * </ul>
     *
     * @param results A list of {@link SampleResult} objects to be processed.
     * @param context The {@link BackendListenerContext} providing context for the operation.
     */
    @Override
    public void handleSampleResults(List<SampleResult> results, BackendListenerContext context) {
        for (SampleResult sr : results) {
            try {
                if (samplersList.isEmpty()
                        || (useRegexForSamplerList && sr.getSampleLabel().matches(samplersList))
                        || (!useRegexForSamplerList && samplersToFilter.contains(sr.getSampleLabel()))
                ) {
                    trackRequest(testName, sr);
                }
            } catch (Exception e) {
                log.error("Error processing sample result", e);
            }
        }
    }

    /**
     * Cleans up resources and flushes telemetry data at the end of a test.
     *
     * @param context The {@link BackendListenerContext} providing context information for the tear-down process.
     * @throws Exception If an error occurs during the tear-down process.
     */
    @Override
    public void teardownTest(BackendListenerContext context) throws Exception {
        samplersToFilter.clear();
        telemetryClient.flush();
        super.teardownTest(context);
    }
}
