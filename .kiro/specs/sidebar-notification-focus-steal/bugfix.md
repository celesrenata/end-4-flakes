# Bugfix Requirements Document

## Introduction

When a notification popup appears while the user is actively typing in the sidebar left AI chat panel's `messageInputField`, keyboard focus is stolen from the input field and never automatically restored. The user must manually click the input field to resume typing. This degrades the typing experience and interrupts workflow, especially for users who receive frequent notifications.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a notification arrives and the NotificationPopup becomes visible while the user has active keyboard focus on messageInputField in the sidebar left AI chat panel THEN the system loses keyboard focus from messageInputField without any mechanism to restore it

1.2 WHEN a notification arrives and the sidebar is in popped-out mode (using WlrKeyboardFocus.OnDemand) THEN the system allows the Overlay-layer NotificationPopup to displace keyboard focus from the sidebar panel with no recovery path

1.3 WHEN a notification arrives and the sidebar is in non-popped-out mode (using HyprlandFocusGrab) THEN the system allows the Overlay-layer NotificationPopup to disrupt the focus grab without triggering a re-focus of the active input field

### Expected Behavior (Correct)

2.1 WHEN a notification arrives and the NotificationPopup becomes visible while the user has active keyboard focus on messageInputField THEN the system SHALL restore keyboard focus to messageInputField after the notification popup appears

2.2 WHEN a notification arrives and the sidebar is in popped-out mode (using WlrKeyboardFocus.OnDemand) THEN the system SHALL ensure the NotificationPopup does not request keyboard focus and the sidebar retains its keyboard focus state

2.3 WHEN a notification arrives and the sidebar is in non-popped-out mode (using HyprlandFocusGrab) THEN the system SHALL re-establish focus on the previously focused input field after the transient Overlay surface appears

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a notification arrives while the sidebar AI chat panel is NOT open or NOT focused THEN the system SHALL CONTINUE TO display the notification popup without altering focus state of other windows

3.2 WHEN the user clicks outside the sidebar (non-popped-out mode) THEN the system SHALL CONTINUE TO close the sidebar via HyprlandFocusGrab.onCleared

3.3 WHEN the user interacts with the notification popup directly (e.g. clicking dismiss or action buttons) THEN the system SHALL CONTINUE TO handle those interactions normally

3.4 WHEN the notification popup disappears (all notifications dismissed or timed out) THEN the system SHALL CONTINUE TO not forcibly move focus to any particular element

3.5 WHEN the sidebar is closed and a notification arrives THEN the system SHALL CONTINUE TO not open or focus the sidebar

---

## Bug Condition (Formal)

```pascal
FUNCTION isBugCondition(X)
  INPUT: X of type FocusEvent
  OUTPUT: boolean
  
  // Returns true when the notification popup becomes visible
  // while the messageInputField has active keyboard focus
  RETURN X.notificationPopupBecomesVisible = true
     AND X.messageInputFieldHasActiveFocus = true
     AND X.sidebarLeftIsOpen = true
END FUNCTION
```

```pascal
// Property: Fix Checking — Focus Restoration
FOR ALL X WHERE isBugCondition(X) DO
  result ← handleNotificationAppearance'(X)
  ASSERT result.messageInputFieldHasActiveFocus = true
END FOR
```

```pascal
// Property: Preservation Checking — Non-buggy inputs unchanged
FOR ALL X WHERE NOT isBugCondition(X) DO
  ASSERT handleNotificationAppearance(X) = handleNotificationAppearance'(X)
END FOR
```
