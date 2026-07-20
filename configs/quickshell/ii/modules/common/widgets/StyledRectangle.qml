import QtQuick
import qs.modules.common as C

// This is to enable future fancy styles for rectangles.
Rectangle {
    enum ContentLayer { Background, Pane, Group, Subgroup, Control }
    property var contentLayer: StyledRectangle.ContentLayer.Pane

    color: switch(contentLayer) {
        case StyledRectangle.ContentLayer.Background: C.Appearance.colors.colLayer0;
        case StyledRectangle.ContentLayer.Pane: C.Appearance.colors.colLayer1;
        case StyledRectangle.ContentLayer.Group: C.Appearance.colors.colLayer2;
        case StyledRectangle.ContentLayer.Subgroup: C.Appearance.colors.colLayer3;
        case StyledRectangle.ContentLayer.Control: C.Appearance.colors.colLayer4;
        default: C.Appearance.colors.colLayer1;
    }
}
