import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 */
QtObject {
    property string role
    property string content
    property string rawContent
    property string model
    property bool thinking: true
    property bool done: false
    property var annotations: []
    property var annotationSources: []
    property list<string> searchQueries: []
    property string functionName
    property var functionCall
    property string functionResponse
    property bool functionPending: false
    property string pendingMcpTool: ""
    property var pendingMcpArgs: ({})
    property bool visibleToUser: true
    // Legacy: base64-encoded image thumbnails (Context Lens)
    property var images: []
    // File-based attachments: [{name, path, type, size}]
    // path is relative to Directories.aiAttachments
    property var attachments: []
}
