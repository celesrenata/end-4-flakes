pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Detects AWS credential files and region configuration for Bedrock provider.
 * Checks ~/.aws/credentials.bedrock (preferred) then ~/.aws/credentials (fallback).
 * Parses ~/.aws/config for the [default] profile region value.
 */
Singleton {
    id: root

    // State properties
    property string credentialsFilePath: ""
    property bool credentialsDetected: false
    property string region: "us-west-2"
    property bool awsCliAvailable: false
    property string statusMessage: ""

    Component.onCompleted: {
        awsCliCheckProcess.running = true;
    }

    // Step 1: Check if aws CLI is available
    Process {
        id: awsCliCheckProcess
        command: ["which", "aws"]
        stdout: StdioCollector {
            onStreamFinished: {
                // which exits 0 if found, non-zero if not
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.awsCliAvailable = true;
                root.statusMessage = "AWS CLI found";
                // Proceed to check credentials.bedrock
                credBedrockCheckProcess.running = true;
            } else {
                root.awsCliAvailable = false;
                root.statusMessage = "AWS CLI not found. Install the aws-cli package to use Bedrock.";
            }
        }
    }

    // Step 2: Check ~/.aws/credentials.bedrock existence
    Process {
        id: credBedrockCheckProcess
        command: ["test", "-f", StandardPaths.home + "/.aws/credentials.bedrock"]
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.credentialsFilePath = StandardPaths.home + "/.aws/credentials.bedrock";
                root.credentialsDetected = true;
                root.statusMessage = "Credentials detected: " + root.credentialsFilePath;
                // Proceed to read region
                regionCheckProcess.running = true;
            } else {
                // Fall back to standard credentials
                credStandardCheckProcess.running = true;
            }
        }
    }

    // Step 3: Fall back to ~/.aws/credentials
    Process {
        id: credStandardCheckProcess
        command: ["test", "-f", StandardPaths.home + "/.aws/credentials"]
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.credentialsFilePath = StandardPaths.home + "/.aws/credentials";
                root.credentialsDetected = true;
                root.statusMessage = "Credentials detected: " + root.credentialsFilePath;
                // Proceed to read region
                regionCheckProcess.running = true;
            } else {
                root.credentialsDetected = false;
                root.statusMessage = "No AWS credentials found. Create ~/.aws/credentials.bedrock with access key on line 1 and secret key on line 2.";
            }
        }
    }

    // Step 4: Parse ~/.aws/config for region
    Process {
        id: regionCheckProcess
        command: ["cat", StandardPaths.home + "/.aws/config"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed = root.parseRegionFromConfig(text);
                if (parsed !== "") {
                    root.region = parsed;
                }
                // else keep default "us-west-2"
            }
        }
        onExited: function(exitCode, exitStatus) {
            // If cat fails (file doesn't exist), keep default region
        }
    }

    // Pure function: parse region from AWS config file content
    function parseRegionFromConfig(configText) {
        var lines = configText.split("\n");
        var inDefaultSection = false;
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].split("\r").join("").trim();
            // Check for section headers
            if (line.indexOf("[") === 0) {
                if (line === "[default]") {
                    inDefaultSection = true;
                } else {
                    inDefaultSection = false;
                }
                continue;
            }
            if (inDefaultSection && line.indexOf("region") === 0) {
                var eqIdx = line.indexOf("=");
                if (eqIdx !== -1) {
                    var value = line.substring(eqIdx + 1).trim();
                    if (value.length > 0) {
                        return value;
                    }
                }
            }
        }
        return "";
    }
}
