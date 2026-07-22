import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: searchPanel

    // Search state
    property string keyword: ""
    property string dateStart: ""
    property string dateEnd: ""
    property string subjectFilter: ""
    property string groupFilter: ""

    // Results state (bound from parent)
    property int currentMatchIndex: 0
    property int totalMatches: 0

    // Signals
    signal searchRequested()
    signal nextMatch()
    signal prevMatch()
    signal clearSearch()
    signal closeSearch()

    // Validation
    readonly property bool keywordValid: keyword.length >= 2 || keyword.length === 0
    readonly property bool hasActiveSearch: keyword.length >= 2 || dateStart.length > 0 || dateEnd.length > 0 || subjectFilter.length > 0 || groupFilter.length > 0

    implicitHeight: contentColumn.implicitHeight + 16

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        // Header with close button
        RowLayout {
            Layout.fillWidth: true

            StyledText {
                text: Translation.tr("Search")
                font.bold: true
                font.pixelSize: Appearance.font.pixelSize.normal
                Layout.fillWidth: true
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 14
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: searchPanel.closeSearch()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSurface
                }
            }
        }

        // Keyword input
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                border.color: !searchPanel.keywordValid ? Appearance.m3colors.m3error : (keywordInput.activeFocus ? Appearance.m3colors.m3primary : "transparent")
                border.width: keywordInput.activeFocus || !searchPanel.keywordValid ? 1 : 0

                StyledTextInput {
                    id: keywordInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.m3colors.m3onSurface
                    clip: true

                    onTextChanged: {
                        searchPanel.keyword = text;
                        if (text.length >= 2 || text.length === 0) {
                            searchPanel.searchRequested();
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Keyword (min 2 chars)")
                        color: Appearance.m3colors.m3outline
                        font: parent.font
                        visible: !parent.text && !parent.activeFocus
                    }
                }
            }
        }

        // Minimum length hint
        StyledText {
            visible: searchPanel.keyword.length > 0 && searchPanel.keyword.length < 2
            text: Translation.tr("Minimum 2 characters required")
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        // Date range
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                border.color: dateStartInput.activeFocus ? Appearance.m3colors.m3primary : "transparent"
                border.width: dateStartInput.activeFocus ? 1 : 0

                StyledTextInput {
                    id: dateStartInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.m3colors.m3onSurface
                    clip: true

                    onTextChanged: {
                        searchPanel.dateStart = text;
                        searchPanel.searchRequested();
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Start date")
                        color: Appearance.m3colors.m3outline
                        font: parent.font
                        visible: !parent.text && !parent.activeFocus
                    }
                }
            }

            StyledText {
                text: "–"
                color: Appearance.m3colors.m3onSurfaceVariant
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                border.color: dateEndInput.activeFocus ? Appearance.m3colors.m3primary : "transparent"
                border.width: dateEndInput.activeFocus ? 1 : 0

                StyledTextInput {
                    id: dateEndInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.m3colors.m3onSurface
                    clip: true

                    onTextChanged: {
                        searchPanel.dateEnd = text;
                        searchPanel.searchRequested();
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("End date")
                        color: Appearance.m3colors.m3outline
                        font: parent.font
                        visible: !parent.text && !parent.activeFocus
                    }
                }
            }
        }

        // Subject and group filters
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                border.color: subjectInput.activeFocus ? Appearance.m3colors.m3primary : "transparent"
                border.width: subjectInput.activeFocus ? 1 : 0

                StyledTextInput {
                    id: subjectInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.m3colors.m3onSurface
                    clip: true

                    onTextChanged: {
                        searchPanel.subjectFilter = text;
                        searchPanel.searchRequested();
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Subject")
                        color: Appearance.m3colors.m3outline
                        font: parent.font
                        visible: !parent.text && !parent.activeFocus
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                border.color: groupInput.activeFocus ? Appearance.m3colors.m3primary : "transparent"
                border.width: groupInput.activeFocus ? 1 : 0

                StyledTextInput {
                    id: groupInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.m3colors.m3onSurface
                    clip: true

                    onTextChanged: {
                        searchPanel.groupFilter = text;
                        searchPanel.searchRequested();
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Group")
                        color: Appearance.m3colors.m3outline
                        font: parent.font
                        visible: !parent.text && !parent.activeFocus
                    }
                }
            }
        }

        // Results navigation
        RowLayout {
            Layout.fillWidth: true
            visible: searchPanel.hasActiveSearch
            spacing: 4

            StyledText {
                text: searchPanel.totalMatches > 0
                    ? Translation.tr("%1 of %2 matches").arg(searchPanel.currentMatchIndex + 1).arg(searchPanel.totalMatches)
                    : Translation.tr("No matches")
                color: searchPanel.totalMatches > 0 ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
                Layout.fillWidth: true
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 14
                enabled: searchPanel.totalMatches > 0
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: searchPanel.prevMatch()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "navigate_before"
                    iconSize: Appearance.font.pixelSize.normal
                    color: searchPanel.totalMatches > 0 ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                }
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 14
                enabled: searchPanel.totalMatches > 0
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: searchPanel.nextMatch()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "navigate_next"
                    iconSize: Appearance.font.pixelSize.normal
                    color: searchPanel.totalMatches > 0 ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                }
            }

            RippleButton {
                implicitWidth: 56
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: {
                    searchPanel.keyword = "";
                    searchPanel.dateStart = "";
                    searchPanel.dateEnd = "";
                    searchPanel.subjectFilter = "";
                    searchPanel.groupFilter = "";
                    keywordInput.text = "";
                    dateStartInput.text = "";
                    dateEndInput.text = "";
                    subjectInput.text = "";
                    groupInput.text = "";
                    searchPanel.clearSearch();
                }

                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Clear")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3primary
                }
            }
        }
    }
}
