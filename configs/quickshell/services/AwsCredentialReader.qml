pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Detects AWS credential files and region configuration for Bedrock provider.
 * Looks for a [bedrock] profile in ~/.aws/credentials.
 * Reads region from the [bedrock] profile in ~/.aws/credentials, falls back to
 * [profile bedrock] in ~/.aws/config, then [default] region, then "us-west-2".
 */
Singleton {
    id: root

    // State properties
    property string homePath: ""
    property string credentialsFilePath: ""
    property bool credentialsDetected: false
    property string region: "us-west-2"
    property string profile: "bedrock"
    property bool awsCliAvailable: false
    property string statusMessage: ""

    Component.onCompleted: {
        homeResolver.running = true;
    }

    // Step 0: Resolve home directory
    Process {
        id: homeResolver
        command: ["bash", "-c", "echo $HOME"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.homePath = text.trim();
                awsCliCheckProcess.running = true;
            }
        }
    }

    // Step 1: Check if aws CLI is available
    Process {
        id: awsCliCheckProcess
        command: ["which", "aws"]
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.awsCliAvailable = true;
                root.statusMessage = "AWS CLI found";
                credCheckProcess.running = true;
            } else {
                root.awsCliAvailable = false;
                root.statusMessage = "AWS CLI not found. Install the aws-cli package to use Bedrock.";
            }
        }
    }

    // Step 2: Check ~/.aws/credentials exists and has [bedrock] profile
    Process {
        id: credCheckProcess
        command: ["bash", "-c", "grep -q '\\[bedrock\\]' \"$HOME/.aws/credentials\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.credentialsFilePath = root.homePath + "/.aws/credentials";
                root.credentialsDetected = true;
                root.statusMessage = "Credentials detected: [bedrock] profile in " + root.credentialsFilePath;
                // Read region from credentials file
                regionFromCredentialsProcess.running = true;
            } else {
                root.credentialsDetected = false;
                root.statusMessage = "No [bedrock] profile found in ~/.aws/credentials. Add a [bedrock] section with aws_access_key_id and aws_secret_access_key.";
            }
        }
    }

    // Step 3: Parse region from [bedrock] section in ~/.aws/credentials
    Process {
        id: regionFromCredentialsProcess
        command: ["cat", root.homePath + "/.aws/credentials"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed = root.parseProfileValue(text, "bedrock", "region");
                if (parsed !== "") {
                    root.region = parsed;
                } else {
                    // Fall back to config file
                    regionFromConfigProcess.running = true;
                }
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) {
                // credentials file unreadable, try config
                regionFromConfigProcess.running = true;
            }
        }
    }

    // Step 4: Fall back to ~/.aws/config for region
    Process {
        id: regionFromConfigProcess
        command: ["cat", root.homePath + "/.aws/config"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Try [profile bedrock] first, then [default]
                var parsed = root.parseProfileValue(text, "profile bedrock", "region");
                if (parsed === "") {
                    parsed = root.parseProfileValue(text, "default", "region");
                }
                if (parsed !== "") {
                    root.region = parsed;
                }
                // else keep default "us-west-2"
            }
        }
        onExited: function(exitCode, exitStatus) {
            // If cat fails, keep default region
        }
    }

    // Pure function: parse a key value from a specific section in INI-style file
    function parseProfileValue(fileContent, sectionName, key) {
        var lines = fileContent.split("\n");
        var inSection = false;
        var sectionHeader = "[" + sectionName + "]";
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].split("\r").join("").trim();
            if (line.indexOf("[") === 0) {
                if (line === sectionHeader) {
                    inSection = true;
                } else {
                    if (inSection) {
                        break; // Left the target section
                    }
                }
                continue;
            }
            if (inSection) {
                var eqIdx = line.indexOf("=");
                if (eqIdx !== -1) {
                    var k = line.substring(0, eqIdx).trim();
                    var v = line.substring(eqIdx + 1).trim();
                    if (k === key && v.length > 0) {
                        return v;
                    }
                }
            }
        }
        return "";
    }
}
