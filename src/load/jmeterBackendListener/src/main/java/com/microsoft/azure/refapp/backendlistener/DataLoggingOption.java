package com.microsoft.azure.refapp.backendlistener;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Enum representing the options for data logging.
 */
public enum DataLoggingOption {
    /**
     * Log data for every operation.
     */
    ALWAYS("Always"),
    /**
     * Log data only when an operation fails.
     */
    ON_FAILURE("OnFailure"),
    /**
     * Never log data.
     */
    NEVER("Never");

    /**
     * The type of logging option, represented as a String.
     */
    private final String type;

    /**
     * Logger instance.
     */
    private static final Logger log = LoggerFactory.getLogger(AzureBackendClient.class);

    /**
     * Constructor for the enum constants.
     *
     * @param value The string representation of the logging option.
     */
    DataLoggingOption(String value) {
        this.type = value;
    }

    /**
     * Gets the string value of the logging option.
     *
     * @return The string representation of the logging option.
     */
    public String getValue() {
        return type;
    }

    /**
     * Converts a string value to its corresponding {@link DataLoggingOption} enum constant.
     * If the provided value does not match any logging option, it defaults to 'OnFailure'.
     *
     * @param value The string representation of the logging option to convert.
     * @return The corresponding {@link DataLoggingOption} enum constant.
     */
    public static DataLoggingOption fromString(String value) {
        for (DataLoggingOption option : DataLoggingOption.values()) {
            if (option.type.equalsIgnoreCase(value)) {
                return option;
            }
        }

        log.warn("Logging type '{}' is invalid. Defaulting to 'OnFailure'", value);
        return ON_FAILURE;
    }

    /**
     * Determines whether logging should occur based on the current logging option and the status of the operation.
     *
     * @param isSampleSuccessful Indicates whether the operation, candidate to be logged, was successful.
     * @return True if logging should occur, false otherwise.
     */
    public boolean shouldLog(boolean isSampleSuccessful) {
        return this == DataLoggingOption.ALWAYS
                || (this == DataLoggingOption.ON_FAILURE && !isSampleSuccessful);
    }
}
