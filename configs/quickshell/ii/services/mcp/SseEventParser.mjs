// configs/quickshell/ii/services/mcp/SseEventParser.mjs

/**
 * Creates a new SSE event parser instance.
 * @returns {object} Parser with feedLine(line), end(), reset(), and onEvent callback
 */
export function createParser() {
    let eventType = "";
    let dataBuffer = [];
    let lastEventId = "";
    let onEvent = null;   // (event: { type, data, lastEventId }) => void
    let totalDataSize = 0;
    const MAX_DATA_SIZE = 10 * 1024 * 1024; // 10 MB

    function feedLine(line) {
        // Blank line → emit event
        if (line === "" || line === "\r") {
            if (dataBuffer.length > 0) {
                const data = dataBuffer.join("\n");
                const type = eventType || "message";

                let parsedData;
                try {
                    parsedData = JSON.parse(data);
                } catch (e) {
                    parsedData = data; // Pass raw string if not valid JSON
                }

                if (onEvent) {
                    onEvent({ type: type, data: parsedData, lastEventId: lastEventId });
                }
            }
            // Reset buffer
            eventType = "";
            dataBuffer = [];
            totalDataSize = 0;
            return { emitted: true };
        }

        // Comment line
        if (line.startsWith(":")) {
            return { emitted: false };
        }

        // Parse field
        const colonIdx = line.indexOf(":");
        let field, value;
        if (colonIdx === -1) {
            field = line;
            value = "";
        } else {
            field = line.substring(0, colonIdx);
            value = line.substring(colonIdx + 1);
            // Strip single leading space
            if (value.startsWith(" ")) {
                value = value.substring(1);
            }
        }

        switch (field) {
            case "event":
                eventType = value;
                break;
            case "data":
                totalDataSize += value.length + 1; // +1 for newline separator
                if (totalDataSize > MAX_DATA_SIZE) {
                    return { emitted: false, error: "size_limit_exceeded" };
                }
                dataBuffer.push(value);
                break;
            case "id":
                lastEventId = value;
                break;
            case "retry":
                // Ignored for now (could be used for reconnection intervals)
                break;
            default:
                // Unrecognized field — ignore
                break;
        }

        return { emitted: false };
    }

    function end() {
        // Stream ended — discard incomplete event
        eventType = "";
        dataBuffer = [];
        totalDataSize = 0;
    }

    function reset() {
        eventType = "";
        dataBuffer = [];
        totalDataSize = 0;
        lastEventId = "";
    }

    return {
        feedLine,
        end,
        reset,
        get onEvent() { return onEvent; },
        set onEvent(cb) { onEvent = cb; },
        get totalDataSize() { return totalDataSize; }
    };
}
