package com.microsoft.azure.refapp.backendlistener;

import com.microsoft.applicationinsights.TelemetryClient;
import com.microsoft.applicationinsights.telemetry.RequestTelemetry;

import org.apache.commons.lang3.RandomStringUtils;
import org.apache.jmeter.config.Arguments;
import org.apache.jmeter.samplers.SampleResult;
import org.apache.jmeter.visualizers.backend.BackendListenerContext;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.internal.util.reflection.Whitebox;
import org.mockito.runners.MockitoJUnitRunner;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;

import static junit.framework.TestCase.fail;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.any;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.verify;

@RunWith(MockitoJUnitRunner.class)
public class TestAzureBackendClient {

    @Mock
    private TelemetryClient telemetryClient;

    @InjectMocks
    private final AzureBackendClient client = new AzureBackendClient();

    private BackendListenerContext context;

    @Before
    public void setUp() {
        Arguments args = new Arguments();
        args.addArgument("testName", "test-1");
        context = new BackendListenerContext(args);
        Whitebox.setInternalState(client, "testName", "test-1");
        Whitebox.setInternalState(client, "samplersToFilter", new HashSet<>());
        Whitebox.setInternalState(client, "logResponseData", DataLoggingOption.ON_FAILURE);
        Whitebox.setInternalState(client, "logSampleData", DataLoggingOption.ON_FAILURE);
    }

    @Test
    public void testGetDefaultParameters() {
        Arguments args = client.getDefaultParameters();
        assertNotNull(args);
    }

    @Test
    public void testHandleSampleResults() {
        doNothing().when(telemetryClient).trackRequest(any());

        SampleResult sr = new SampleResult();
        List<SampleResult> list = new ArrayList<>();
        list.add(sr);

        try {
            client.handleSampleResults(list, context);
        } catch (Exception e) {
            fail(e.toString());
        }
    }

    @Test
    public void testDoNotLogDataOnSuccess() {
        doNothing().when(telemetryClient).trackRequest(any(RequestTelemetry.class));
        Whitebox.setInternalState(client, "logResponseData", DataLoggingOption.ON_FAILURE);
        Whitebox.setInternalState(client, "logSampleData", DataLoggingOption.ON_FAILURE);

        SampleResult sr = new SampleResult();
        sr.setSampleLabel("test-1");
        sr.setSuccessful(true);
        sr.setResponseCode("200");
        sr.setResponseMessage("OK");
        sr.setResponseData("Test response data".getBytes());
        sr.setDataType(SampleResult.TEXT);
        sr.setSampleCount(1);
        sr.setSamplerData("Test sampler data");
        List<SampleResult> list = new ArrayList<>();
        list.add(sr);

        client.handleSampleResults(list, context);

        ArgumentCaptor<RequestTelemetry> argument = ArgumentCaptor.forClass(RequestTelemetry.class);
        verify(telemetryClient).trackRequest(argument.capture());
        assertFalse(argument.getValue().getProperties().containsKey("SampleData"));
        assertFalse(argument.getValue().getProperties().containsKey("ResponseData"));
    }

    @Test
    public void testDoLogDataOnSuccess() {
        doNothing().when(telemetryClient).trackRequest(any(RequestTelemetry.class));
        Whitebox.setInternalState(client, "logResponseData", DataLoggingOption.ALWAYS);
        Whitebox.setInternalState(client, "logSampleData", DataLoggingOption.ALWAYS);

        SampleResult sr = new SampleResult();
        sr.setSampleLabel("test-1");
        sr.setSuccessful(true);
        sr.setResponseCode("200");
        sr.setResponseMessage("OK");
        sr.setResponseData("Test response data".getBytes());
        sr.setDataType(SampleResult.TEXT);
        sr.setSampleCount(1);
        sr.setSamplerData("Test sampler data");
        List<SampleResult> list = new ArrayList<>();
        list.add(sr);

        client.handleSampleResults(list, context);

        ArgumentCaptor<RequestTelemetry> argument = ArgumentCaptor.forClass(RequestTelemetry.class);
        verify(telemetryClient).trackRequest(argument.capture());
        assertEquals("Test sampler data", argument.getValue().getProperties().get("SampleData"));
        assertEquals("Test response data", argument.getValue().getProperties().get("ResponseData"));
    }

    @Test
    public void testDoLogDataOnFailure() {
        doNothing().when(telemetryClient).trackRequest(any(RequestTelemetry.class));
        Whitebox.setInternalState(client, "logResponseData", DataLoggingOption.ON_FAILURE);
        Whitebox.setInternalState(client, "logSampleData", DataLoggingOption.ON_FAILURE);

        SampleResult sr = new SampleResult();
        sr.setSampleLabel("test-1");
        sr.setSuccessful(false);
        sr.setResponseCode("200");
        sr.setResponseMessage("OK");
        sr.setErrorCount(1);
        sr.setResponseData("Test response data".getBytes());
        sr.setDataType(SampleResult.TEXT);
        sr.setSampleCount(1);
        sr.setSamplerData("Test sampler data");
        List<SampleResult> list = new ArrayList<>();
        list.add(sr);

        client.handleSampleResults(list, context);

        ArgumentCaptor<RequestTelemetry> argument = ArgumentCaptor.forClass(RequestTelemetry.class);
        verify(telemetryClient).trackRequest(argument.capture());
        assertEquals("Test sampler data", argument.getValue().getProperties().get("SampleData"));
        assertEquals("Test response data", argument.getValue().getProperties().get("ResponseData"));
    }

    @Test
    public void testDoNotLogDataOnFailure() {
        doNothing().when(telemetryClient).trackRequest(any(RequestTelemetry.class));
        Whitebox.setInternalState(client, "logResponseData", DataLoggingOption.NEVER);
        Whitebox.setInternalState(client, "logSampleData", DataLoggingOption.NEVER);

        SampleResult sr = new SampleResult();
        sr.setSampleLabel("test-1");
        sr.setSuccessful(false);
        sr.setResponseCode("200");
        sr.setResponseMessage("OK");
        sr.setErrorCount(1);
        sr.setResponseData("Test response data".getBytes());
        sr.setDataType(SampleResult.TEXT);
        sr.setSampleCount(1);
        sr.setSamplerData("Test sampler data");
        List<SampleResult> list = new ArrayList<>();
        list.add(sr);

        client.handleSampleResults(list, context);

        ArgumentCaptor<RequestTelemetry> argument = ArgumentCaptor.forClass(RequestTelemetry.class);
        verify(telemetryClient).trackRequest(argument.capture());
        assertFalse(argument.getValue().getProperties().containsKey("SampleData"));
        assertFalse(argument.getValue().getProperties().containsKey("ResponseData"));
    }

    @Test
    public void testTruncateData() {
        doNothing().when(telemetryClient).trackRequest(any(RequestTelemetry.class));
        Whitebox.setInternalState(client, "logResponseData", DataLoggingOption.ON_FAILURE);
        Whitebox.setInternalState(client, "logSampleData", DataLoggingOption.ON_FAILURE);

        SampleResult sr = new SampleResult();
        sr.setSampleLabel("test-1");
        sr.setSuccessful(false);
        sr.setResponseCode("200");
        sr.setResponseMessage("OK");
        sr.setErrorCount(1);
        sr.setResponseData(RandomStringUtils.randomAlphanumeric(2048).getBytes());
        sr.setDataType(SampleResult.TEXT);
        sr.setSampleCount(1);
        sr.setSamplerData(RandomStringUtils.randomAlphanumeric(2048));
        List<SampleResult> list = new ArrayList<>();
        list.add(sr);

        client.handleSampleResults(list, context);

        ArgumentCaptor<RequestTelemetry> argument = ArgumentCaptor.forClass(RequestTelemetry.class);
        verify(telemetryClient).trackRequest(argument.capture());
        assertTrue(argument.getValue().getProperties().get("SampleData").endsWith("[TRUNCATED]"));
        assertTrue(argument.getValue().getProperties().get("ResponseData").endsWith("[TRUNCATED]"));
    }

    @Test
    public void testDoNotLogBinaryData() {
        doNothing().when(telemetryClient).trackRequest(any(RequestTelemetry.class));
        Whitebox.setInternalState(client, "logResponseData", DataLoggingOption.ON_FAILURE);
        Whitebox.setInternalState(client, "logSampleData", DataLoggingOption.ON_FAILURE);

        SampleResult sr = new SampleResult();
        sr.setSampleLabel("test-1");
        sr.setSuccessful(false);
        sr.setResponseCode("200");
        sr.setResponseMessage("OK");
        sr.setErrorCount(1);
        sr.setResponseData(RandomStringUtils.randomAlphanumeric(2048).getBytes());
        sr.setDataType(SampleResult.BINARY);
        sr.setSampleCount(1);
        sr.setSamplerData(RandomStringUtils.randomAlphanumeric(2048));
        List<SampleResult> list = new ArrayList<>();
        list.add(sr);

        client.handleSampleResults(list, context);

        ArgumentCaptor<RequestTelemetry> argument = ArgumentCaptor.forClass(RequestTelemetry.class);
        verify(telemetryClient).trackRequest(argument.capture());
        assertEquals("[BINARY DATA]", argument.getValue().getProperties().get("SampleData"));
    }
}
