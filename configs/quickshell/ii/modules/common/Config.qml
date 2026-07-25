pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    // Set a nested value using an array of keys (e.g., ["ai", "customProviders"])
    function setNestedField(path, value) {
        root.setNestedValue(path.join("."), value);
    }

    FileView {
        path: root.filePath
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter
            property JsonObject policies: JsonObject {
                property int ai: 1 // 0: No | 1: Yes | 2: Local
                property int weeb: 1 // 0: No | 1: Open | 2: Closet
            }

            property JsonObject ai: JsonObject {
                property string defaultProvider: "openai" // Provider to auto-discover first on startup: openai, anthropic, gemini, mistral, bedrock, ollama
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal! Make sure you answer precisely without hallucination and prefer bullet points over walls of text. You can have a friendly greeting at the beginning of the conversation, but don't repeat the user's question\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n"
                property string tool: "functions" // search, functions, or none
                property list<var> extraModels: [
                    {
                        "api_format": "openai", // Most of the time you want "openai". Use "gemini" for Google's models
                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is DeepSeek R1 Distill LLaMA 70B",
                        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                        "homepage": "https://openrouter.ai/deepseek/deepseek-r1-distill-llama-70b:free", // Not mandatory
                        "icon": "spark-symbolic", // Not mandatory
                        "key_get_link": "https://openrouter.ai/settings/keys", // Not mandatory
                        "key_id": "openrouter",
                        "model": "deepseek/deepseek-r1-distill-llama-70b:free",
                        "name": "Custom: DS R1 Dstl. LLaMA 70B",
                        "requires_key": true
                    }
                ]
                property list<var> customProviders: []
            }

            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen
                property bool transparency: false
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                }
            }

            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: true
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 90 // Realistically should already provide some protection when it's 99...
                }
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "kcmshell6-bluetooth"
                property string network: "kcmshell6-network"
                property string networkEthernet: "kcmshell6-network"
                property string taskManager: "plasma-systemmonitor --page-name Processes"
                property string terminal: "kitty -1" // This is only for shell actions
            }

            property JsonObject background: JsonObject {
                property bool showClock: false
                property bool fixedClockPosition: false
                property real clockX: -500
                property real clockY: -500
                property string wallpaperPath: ""
                property string thumbnailPath: ""
                property JsonObject parallax: JsonObject {
                    property bool enableWorkspace: true
                    property real workspaceZoom: 1.07 // Relative to your screen, not wallpaper size
                    property bool enableSidebar: true
                }
            }

            property JsonObject bar: JsonObject {
                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
                property bool borderless: false // true for no grouping of items
                property string topLeftIcon: "spark" // Options: distro, spark
                property bool showBackground: true
                property bool verbose: true
                property JsonObject resources: JsonObject {
                    property bool alwaysShowSwap: true
                    property bool alwaysShowCpu: false
                }
                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: true
                    property bool showColorPicker: false
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: true
                    property bool showDarkModeToggle: true
                    property bool showNightLightToggle: true
                    property bool showPerformanceProfileToggle: false
                }
                property JsonObject tray: JsonObject {
                    property bool monochromeIcons: true
                }
                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: true
                    property int shown: 10
                    property bool showAppIcons: true
                    property bool alwaysShowNumbers: false
                    property int showNumberDelay: 300 // milliseconds
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property bool automaticSuspend: true
                property int suspend: 3
            }

            property JsonObject dock: JsonObject {
                property bool enable: true
                property bool monochromeIcons: true
                property real height: 60
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries
                    "org.kde.dolphin", "kitty",]
                property list<string> ignoredAppRegexes: []
            }

            property JsonObject language: JsonObject {
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                }
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject osd: JsonObject {
                property int timeout: 1000
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property real scale: 0.18 // Relative to screen size
                property real rows: 2
                property real columns: 5
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
            }

            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com"]
                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject prefix: JsonObject {
                    property string action: "/"
                    property string ai: "?"
                    property string clipboard: ";"
                    property string emojis: ":"
                }
            }

            property JsonObject sidebar: JsonObject {
                property bool keepRightSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                }
            }

            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm"
                property string dateFormat: "ddd, dd/MM"
            }

            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }

            property JsonObject screenshotTool: JsonObject {
                property bool showContentRegions: true
            }

            property JsonObject terminal: JsonObject {
                property int opacity: 80 // Terminal opacity percentage (10-100)
                property bool transparency: true // Enable/disable terminal transparency
            }

            property JsonObject dictation: JsonObject {
                property bool enabled: true
                property string activationKey: "Control_R"
                property int doubleTapMs: 600
                property int debounceMs: 500 // Debounce window (ms) after activation; 0-2000, 0 disables
                property int silenceTimeoutMs: 5000
                property int maxDurationMs: 60000
                property string provider: "openai"
                property string model: "whisper-1"
                property string streamingEndpoint: ""
                property int chunkDurationMs: 3000
                property string ttsProvider: "openai" // none, piper, espeak-ng, openai
                property string ttsVoice: "nova" // Provider-specific voice ID
                property bool talkback: true // Enable TTS playback
                property string verbosity: "concise" // concise, normal, detailed
                property string intentMode: "heuristic" // heuristic, ai
                property string httpEndpoint: "" // HTTP batch endpoint for STT
                property string ttsHttpEndpoint: "" // HTTP endpoint for OpenAI-compatible TTS
                property bool smartRouting: false // Smart Dictation Routing — route voice input by intent
                property string voiceBackend: "none" // "none" | "nova-sonic" | "openai-realtime"
                property string voiceSystemPrompt: "You are a helpful voice assistant on a Linux desktop (Hyprland + Quickshell). You can execute shell commands, control the desktop, check system info, get weather data, and launch apps. Keep answers concise and conversational — the user is listening, not reading. For time/date queries, always use shell_exec with the 'date' command to get the current local time — never guess or use stale information. Respond in 1-3 sentences unless the user asks for detail."

                // Local STT provider configurations
                property JsonObject sttProviders: JsonObject {
                    property JsonObject whisperCpp: JsonObject {
                        property string endpoint: "http://localhost:8080"
                        property string protocol: "rest"
                        property string model: "base.en"
                        property string language: "en"
                        property real temperature: 0.0
                    }
                    property JsonObject fasterWhisper: JsonObject {
                        property string endpoint: "http://localhost:8000"
                        property string protocol: "rest"
                        property string model: "base"
                        property string language: "en"
                        property real temperature: 0.0
                    }
                    property JsonObject vosk: JsonObject {
                        property string endpoint: "ws://localhost:2700"
                        property string protocol: "websocket"
                        property string model: "vosk-model-en-us-0.22"
                        property string language: "en"
                    }
                    property JsonObject whisperLive: JsonObject {
                        property string endpoint: "ws://localhost:9090"
                        property string protocol: "websocket"
                        property string model: "base.en"
                        property string language: "en"
                    }
                }

                // Local TTS provider configurations
                property JsonObject ttsProviders: JsonObject {
                    property JsonObject piper: JsonObject {
                        property string endpoint: "tcp://localhost:10200"
                        property string protocol: "wyoming"
                        property string voice: "en_US-lessac-medium"
                        property string model: ""
                    }
                    property JsonObject coqui: JsonObject {
                        property string endpoint: "http://localhost:5002"
                        property string protocol: "rest"
                        property string voice: "tts_models/en/ljspeech/tacotron2-DDC"
                        property string language: "en"
                    }
                    property JsonObject mimic3: JsonObject {
                        property string endpoint: "http://localhost:59125"
                        property string protocol: "rest"
                        property string voice: "en_US/ljspeech_low"
                        property string language: "en"
                    }
                    property JsonObject espeakNg: JsonObject {
                        property string voice: "en"
                        property int speed: 175
                        property int pitch: 50
                    }
                }
            }

            property JsonObject cheatsheet: JsonObject {
                property string superKey: "" // Override Super key display (e.g. "⌘" for Mac users)
                property bool useMacSymbol: false // Use Mac-style modifier symbols (⌃ ⌥ ⇧)
                property bool useFnSymbol: true // Use nerd font function key symbols
                property bool useMouseSymbol: true // Use nerd font mouse symbols
                property bool splitButtons: false // Show each modifier as separate key cap
                property JsonObject fontSize: JsonObject {
                    property int key: 0 // 0 = use default
                    property int comment: 0 // 0 = use default (Appearance.font.pixelSize.smaller)
                }
            }

            property JsonObject blur: JsonObject {
                property bool enabled: true
                property bool xray: false
                property int size: 8
                property int passes: 4
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                property JsonObject forceMonitor: JsonObject {
                    property bool enable: false
                    property string name: "" // Name of the monitor to show notifications on, like "eDP-1". Find out with 'hyprctl monitors' command
                }
            }
        }
    }
}
