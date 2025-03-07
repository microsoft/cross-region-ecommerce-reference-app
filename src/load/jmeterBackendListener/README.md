# Application Insights JMeter Backend Listener

A JMeter plug-in that enables the sending of test results and telemetry to Azure Application Insights.

## Overview

### Description

JMeter Backend Azure is a JMeter plugin enabling you to send test results to an Azure Application Insights.

The following test results metrics are exposed by the plugin.

- TestStartTime
- SampleStartTime
- SampleEndTime
- ResponseCode
- Duration
- URL
- SampleLabel
- SampleCount
- ErrorCount
- Bytes
- SentBytes
- ConnectTime
- IdleTime
- ThreadName
- GrpThreads
- AllThreads
- (Optional) aih.{ResponseHeader}
- (Optional) ResponseData
- (Optional) SampleData

### Plugin installation

1. Build the Maven project (`mvn package`).
2. The build produces two *jars*:
   1. The Backend Listener jar: `{projectDir}/target/refapp.backendlistener-{VERSION}-SNAPSHOT.jar`
   2. The Application Insights Java agent jar: `{projectDir}/target/agents/applicationinsights-agent-{VERSION}.jar`

#### Running from a local instance of JMeter
1. Copy the Backend Listener jar to your JMeter extension lib:
```bash
mv $PROJECT_HOME/target/refapp.backendlistener-{VERSION}-SNAPSHOT.jar $JMETER_HOME/lib/ext/
```
2. Set the JMeter JVM to run with the Application Insights Java agent attached, by setting the `JVM_ARGS` environment variable accordingly:
```
# PowerShell:
$Env:JVM_ARGS="-javaagent:{projectDir}\target\agents\applicationinsights-agent-{VERSION}.jar"

# Bash:
export JVM_ARGS="-javaagent:{projectDir}/target/agents/applicationinsights-agent-{VERSION}.jar"
```

3. Run JMeter locally
```dtd
./$JMETER_HOME/bin/jmeter-n.cmd <JMXScript>
```

#### Running from Azure Load Testing
1. Define a new Azure Load Testing test suite (JMX type test suite), by uploading the following:
   1. The `.JMX` script definition
   2. The Backend Listener jar
   3. The Application Insights Java agent jar
2. On *"Parameters"* tab, define the following environment variables:
   1. `APPLICATIONINSIGHTS_CONNECTION_STRING=<TargetAppInsightsConnectionString>`
   2. `JVM_ARGS=-javaagent:/jmeter/lib/ext/applicationinsights-agent-{VERSION}.jar` (the name of the Application Insights Java agent jar)
3. Run the created test

### JMeter configuration

To make JMeter send test result metrics to Azure Application Insights, in your **Test Pan**, right click on
**Thread Group** > Add > Listener > Backend Listener, and choose `com.microsoft.azure.refapp.backendlistener.AzureBackendClient` as `Backend Listener Implementation`.
Then, in the Parameters table, configure the following attributes.

| Attribute | Description | Required |
|---|---|---|
| *testName* | Name of the test. This value is used to differentiate metrics across test runs or plans in Application Insights and allow you to filter them. | Yes |
| *samplersList* | Optional list of samplers separated by a semi-colon (`;`) that the listener will collect and send metrics to Application Insights. If the list is empty, the listener will not filter samplers and send metrics from all of them. Defaults to an empty string. | No |
| *useRegexForSamplerList* | If set to `true` the `samplersList` will be evaluated as a regex to filter samplers. Defaults to `false`. | No |
| *responseHeaders* | Optional list of response headers separated by a semi-colon (`;`) that the listener will collect and send values to Application Insights. | No |
| *logResponseData* | This value indicates whether or not the response data should be captured. Options are `Always`, `OnFailure`, or `Never`. The response data will be captured as a string into the _ResponseData_ property. Defaults to `OnFailure`. | No |
| *logSampleData* | Boolean to indicate whether or not the sample data should be captured. Options are `Always`, `OnFailure`, or `Never`. The sample data will be captured as a string into the _SampleData_ property. Defaults to `OnFailure`. | No |

#### Custom properties

You can add custom data to your metrics by adding properties starting with `ai.`, for example, you might want to provide information related to your environment with the property `ai.environment` and value `staging`.

### Visualization

Test result metrics are available in the **requests** dimension of your Application Insights instance.
In the image you can see an example of how you can visualize the duration of the requests made during your test run.

---

This plugin is inspired by the [jmeter-backend-azure](https://github.com/adrianmo/jmeter-backend-azure/tree/master).
