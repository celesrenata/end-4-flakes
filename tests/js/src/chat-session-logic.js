/**
 * Chat Session Overhaul — pure logic functions extracted for property-based testing.
 * Ports of QML functions used in Ai.qml, AiChat.qml, and DictationService.qml.
 *
 * QML constraints applied:
 * - No spread operator (use Object.assign or manual copy)
 * - No replaceAll (use split/join)
 * - No for...of (use indexed for loops)
 */

/**
 * Serialize a message list to JSON and deserialize it back (round-trip).
 * Each message has {role, rawContent, model, thinking, done, annotations,
 * annotationSources, functionName, functionCall, functionResponse, visibleToUser}.
 * @param {Array<object>} messages
 * @returns {Array<object>} The deserialized array
 */
export function saveLoadRoundTrip(messages) {
    var json = JSON.stringify(messages);
    return JSON.parse(json);
}

/**
 * Validate a session name against rules.
 * Invalid if: empty/whitespace-only, contains "/" or "\", or already exists in existingNames.
 * @param {string} name
 * @param {Array<string>} existingNames
 * @returns {{valid: boolean, reason: string}}
 */
export function validateSessionName(name, existingNames) {
    if (!name || name.trim().length === 0) {
        return { valid: false, reason: "Name cannot be empty or whitespace-only" };
    }
    if (name.indexOf("/") !== -1 || name.indexOf("\\") !== -1) {
        return { valid: false, reason: "Name cannot contain / or \\ characters" };
    }
    for (var i = 0; i < existingNames.length; i++) {
        if (existingNames[i] === name) {
            return { valid: false, reason: "Name already exists" };
        }
    }
    return { valid: true, reason: "" };
}

/**
 * Format the context meter display string.
 * Percentage is Math.round(ratio * 100). Limit formatting:
 * >= 1000000 → "{n/1000000}M", >= 1000 → "{n/1000}k", else raw number.
 * @param {number} ratio - Context usage ratio (0.0 to 1.0+)
 * @param {number} contextLimit - Token limit (positive integer)
 * @returns {string} Formatted string like "42% of 128k"
 */
export function formatContextMeter(ratio, contextLimit) {
    var percentage = Math.round(ratio * 100);
    var limitStr;
    if (contextLimit >= 1000000) {
        limitStr = String(contextLimit / 1000000) + "M";
    } else if (contextLimit >= 1000) {
        limitStr = String(contextLimit / 1000) + "k";
    } else {
        limitStr = String(contextLimit);
    }
    return percentage + "% of " + limitStr;
}

/**
 * Determine if the auto-compact notification should be shown.
 * Returns true if ratio crosses 0.85 threshold from below AND not already shown.
 * @param {number} currentRatio
 * @param {number} previousRatio
 * @param {boolean} alreadyShown
 * @returns {boolean}
 */
export function shouldShowAutoCompact(currentRatio, previousRatio, alreadyShown) {
    if (alreadyShown) {
        return false;
    }
    return previousRatio < 0.85 && currentRatio >= 0.85;
}

/**
 * Filter messages by keyword (case-insensitive substring match on rawContent).
 * Keyword must be >= 2 chars; returns empty array if not.
 * @param {Array<object>} messages - Messages with rawContent field
 * @param {string} keyword
 * @returns {Array<object>} Filtered array
 */
export function filterByKeyword(messages, keyword) {
    if (!keyword || keyword.length < 2) {
        return [];
    }
    var lowerKeyword = keyword.toLowerCase();
    var results = [];
    for (var i = 0; i < messages.length; i++) {
        var content = (messages[i].rawContent || "").toLowerCase();
        if (content.indexOf(lowerKeyword) !== -1) {
            results.push(messages[i]);
        }
    }
    return results;
}

/**
 * Filter messages by timestamp within [startDate, endDate] inclusive.
 * Either bound can be null (unbounded).
 * @param {Array<object>} messages - Messages with timestamp field
 * @param {number|null} startDate - Unix timestamp (inclusive lower bound)
 * @param {number|null} endDate - Unix timestamp (inclusive upper bound)
 * @returns {Array<object>} Filtered array
 */
export function filterByDateRange(messages, startDate, endDate) {
    var results = [];
    for (var i = 0; i < messages.length; i++) {
        var ts = messages[i].timestamp;
        if (startDate !== null && startDate !== undefined && ts < startDate) {
            continue;
        }
        if (endDate !== null && endDate !== undefined && ts > endDate) {
            continue;
        }
        results.push(messages[i]);
    }
    return results;
}

/**
 * Filter sessions by subject (case-insensitive substring match on session.subject field).
 * @param {Array<object>} sessions - Sessions with subject field
 * @param {string} subjectFilter
 * @returns {Array<object>} Filtered array
 */
export function filterBySubject(sessions, subjectFilter) {
    if (!subjectFilter || subjectFilter.length === 0) {
        return sessions;
    }
    var lowerFilter = subjectFilter.toLowerCase();
    var results = [];
    for (var i = 0; i < sessions.length; i++) {
        var subject = (sessions[i].subject || "").toLowerCase();
        if (subject.indexOf(lowerFilter) !== -1) {
            results.push(sessions[i]);
        }
    }
    return results;
}

/**
 * Filter sessions by group (exact match on session.group field).
 * @param {Array<object>} sessions - Sessions with group field
 * @param {string} groupFilter
 * @returns {Array<object>} Filtered array
 */
export function filterByGroup(sessions, groupFilter) {
    if (!groupFilter || groupFilter.length === 0) {
        return sessions;
    }
    var results = [];
    for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].group === groupFilter) {
            results.push(sessions[i]);
        }
    }
    return results;
}

/**
 * Wrapping navigation for search results.
 * direction "next": if currentIndex === totalResults-1, return 0, else currentIndex+1.
 * direction "prev": if currentIndex === 0, return totalResults-1, else currentIndex-1.
 * @param {number} currentIndex
 * @param {number} totalResults
 * @param {string} direction - "next" or "prev"
 * @returns {number} New index
 */
export function wrapSearchIndex(currentIndex, totalResults, direction) {
    if (totalResults <= 0) {
        return 0;
    }
    if (direction === "next") {
        if (currentIndex === totalResults - 1) {
            return 0;
        }
        return currentIndex + 1;
    }
    // direction === "prev"
    if (currentIndex === 0) {
        return totalResults - 1;
    }
    return currentIndex - 1;
}

/**
 * Classify intent of transcribed text.
 * Returns "command" | "dictation" | "ambiguous".
 * Heuristic:
 * - Imperative verb prefix → "command"
 * - Question patterns (starts with question words) → "dictation"
 * - Under 20 words and no match → "ambiguous"
 * @param {string} text
 * @returns {string} "command" | "dictation" | "ambiguous"
 */
export function classifyIntent(text) {
    if (!text || text.trim().length === 0) {
        return "ambiguous";
    }

    var trimmed = text.trim();
    var lowerTrimmed = trimmed.toLowerCase();

    // Imperative verb prefixes
    var commandVerbs = [
        "open", "close", "launch", "set", "change", "toggle", "switch",
        "move", "kill", "run", "show", "hide", "play", "pause", "stop",
        "mute", "unmute", "find", "search", "check", "tell", "give", "list",
        "maximize", "minimize", "resize", "start", "increase", "decrease", "adjust"
    ];

    // Check if first word is a command verb
    var firstWord = lowerTrimmed.split(" ")[0];
    for (var i = 0; i < commandVerbs.length; i++) {
        if (firstWord === commandVerbs[i]) {
            return "command";
        }
    }

    // Question patterns
    var questionWords = [
        "what", "how", "when", "where", "who", "which",
        "why", "can", "could", "would", "should",
        "is", "are", "do", "does", "did", "will"
    ];

    for (var j = 0; j < questionWords.length; j++) {
        if (firstWord === questionWords[j]) {
            return "dictation";
        }
    }

    // Contains question mark → "dictation"
    if (trimmed.indexOf("?") !== -1) {
        return "dictation";
    }

    // Long text (>20 words) without heuristic match → "dictation"
    var words = trimmed.split(/\s+/);
    if (words.length > 20) {
        return "dictation";
    }

    // No heuristic match → ambiguous
    return "ambiguous";
}

/**
 * Route dictation text based on active session.
 * Returns {action: "submit"|"insert"|"skip", target: string}.
 * - Empty/whitespace text → {action:"skip", target:""}
 * - activeSessionName === "Free Dictation" → {action:"submit", target:"Free Dictation"}
 * - Otherwise → {action:"insert", target: activeSessionName}
 * @param {string} text
 * @param {string} activeSessionName
 * @returns {{action: string, target: string}}
 */
export function routeDictation(text, activeSessionName) {
    if (!text || text.trim().length === 0) {
        return { action: "skip", target: "" };
    }
    if (activeSessionName === "Free Dictation") {
        return { action: "submit", target: "Free Dictation" };
    }
    return { action: "insert", target: activeSessionName };
}

/**
 * Validate a group label.
 * Valid if 1-64 chars, not whitespace-only.
 * @param {string} label
 * @returns {{valid: boolean, reason: string}}
 */
export function validateGroupLabel(label) {
    if (!label || label.length === 0) {
        return { valid: false, reason: "Group label cannot be empty" };
    }
    if (label.trim().length === 0) {
        return { valid: false, reason: "Group label cannot be whitespace-only" };
    }
    if (label.length > 64) {
        return { valid: false, reason: "Group label cannot exceed 64 characters" };
    }
    return { valid: true, reason: "" };
}

/**
 * Validate a subject string.
 * Valid if 1-128 chars, not whitespace-only.
 * @param {string} subject
 * @returns {{valid: boolean, reason: string}}
 */
export function validateSubject(subject) {
    if (!subject || subject.length === 0) {
        return { valid: false, reason: "Subject cannot be empty" };
    }
    if (subject.trim().length === 0) {
        return { valid: false, reason: "Subject cannot be whitespace-only" };
    }
    if (subject.length > 128) {
        return { valid: false, reason: "Subject cannot exceed 128 characters" };
    }
    return { valid: true, reason: "" };
}

/**
 * Sort group label strings in case-insensitive alphabetical order.
 * @param {Array<string>} groups
 * @returns {Array<string>} Sorted copy
 */
export function sortGroupHeaders(groups) {
    var copy = [];
    for (var i = 0; i < groups.length; i++) {
        copy.push(groups[i]);
    }
    copy.sort(function(a, b) {
        var lowerA = a.toLowerCase();
        var lowerB = b.toLowerCase();
        if (lowerA < lowerB) return -1;
        if (lowerA > lowerB) return 1;
        return 0;
    });
    return copy;
}

/**
 * Build an error message for HyprMCP verification mismatch.
 * The message must contain both expected and actual values as substrings.
 * @param {string} expected
 * @param {string} actual
 * @returns {string} Error message containing both values
 */
export function verifyMismatchMessage(expected, actual) {
    return "Verification failed: expected " + String(expected) + ", got " + String(actual);
}
