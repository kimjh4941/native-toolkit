package android.library.notification.data.repository

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.domain.model.NotificationCallPerson
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationCustomViewStyleData
import android.library.notification.domain.model.NotificationMessage
import android.library.notification.domain.model.NotificationProgress
import android.library.notification.domain.model.NotificationSchedule
import android.library.notification.domain.model.NotificationStyle

internal fun AndroidNotificationCommand.toPayload(): AndroidNotificationCommandPayload {
    return AndroidNotificationCommandPayload(
        content = content.toPayload(),
        platformOptions = platformOptions
    )
}

internal fun AndroidNotificationCommandPayload.toCommand(): AndroidNotificationCommand {
    return AndroidNotificationCommand(
        content = content.toDomain(),
        platformOptions = platformOptions
    )
}

internal fun NotificationSchedule.toPayload(): NotificationSchedulePayload {
    return NotificationSchedulePayload(
        triggerAtMillis = triggerAtMillis,
        exact = exact,
        allowWhileIdle = allowWhileIdle,
        persistAcrossBoot = persistAcrossBoot,
        alarmType = alarmType
    )
}

internal fun NotificationSchedulePayload.toDomain(): NotificationSchedule {
    return NotificationSchedule(
        triggerAtMillis = triggerAtMillis,
        exact = exact,
        allowWhileIdle = allowWhileIdle,
        persistAcrossBoot = persistAcrossBoot,
        alarmType = alarmType
    )
}

private fun NotificationContent.toPayload(): NotificationContentPayload {
    return NotificationContentPayload(
        id = id,
        title = title,
        message = message,
        tag = tag,
        channel = channel.toPayload(),
        smallIconResId = smallIconResId,
        largeIconResId = largeIconResId,
        priority = priority,
        autoCancel = autoCancel,
        ongoing = ongoing,
        subText = subText,
        showTimestamp = showTimestamp,
        timestampMillis = timestampMillis,
        soundUri = soundUri,
        category = category,
        visibility = visibility,
        color = color,
        number = number,
        ticker = ticker,
        groupKey = groupKey,
        isGroupSummary = isGroupSummary,
        groupAlertBehavior = groupAlertBehavior,
        sortKey = sortKey,
        onlyAlertOnce = onlyAlertOnce,
        localOnly = localOnly,
        silent = silent,
        usesChronometer = usesChronometer,
        timeoutAfterMillis = timeoutAfterMillis,
        progress = progress?.let { NotificationProgressPayload(it.max, it.current, it.indeterminate) },
        style = style.toPayload()
    )
}

private fun NotificationContentPayload.toDomain(): NotificationContent {
    return NotificationContent(
        id = id,
        title = title,
        message = message,
        tag = tag,
        channel = channel.toDomain(),
        smallIconResId = smallIconResId,
        largeIconResId = largeIconResId,
        priority = priority,
        autoCancel = autoCancel,
        ongoing = ongoing,
        subText = subText,
        showTimestamp = showTimestamp,
        timestampMillis = timestampMillis,
        soundUri = soundUri,
        category = category,
        visibility = visibility,
        color = color,
        number = number,
        ticker = ticker,
        groupKey = groupKey,
        isGroupSummary = isGroupSummary,
        groupAlertBehavior = groupAlertBehavior,
        sortKey = sortKey,
        onlyAlertOnce = onlyAlertOnce,
        localOnly = localOnly,
        silent = silent,
        usesChronometer = usesChronometer,
        timeoutAfterMillis = timeoutAfterMillis,
        progress = progress?.let { NotificationProgress(it.max, it.current, it.indeterminate) },
        style = style.toDomain()
    )
}

private fun NotificationChannel.toPayload(): NotificationChannelPayload {
    return NotificationChannelPayload(
        id = id,
        name = name,
        importance = importance,
        description = description,
        showBadge = showBadge,
        enableLights = enableLights,
        lightColor = lightColor,
        enableVibration = enableVibration,
        vibrationPattern = vibrationPattern,
        soundUri = soundUri,
        lockscreenVisibility = lockscreenVisibility,
        groupId = groupId,
        groupName = groupName
    )
}

private fun NotificationChannelPayload.toDomain(): NotificationChannel {
    return NotificationChannel(
        id = id,
        name = name,
        importance = importance,
        description = description,
        showBadge = showBadge,
        enableLights = enableLights,
        lightColor = lightColor,
        enableVibration = enableVibration,
        vibrationPattern = vibrationPattern,
        soundUri = soundUri,
        lockscreenVisibility = lockscreenVisibility,
        groupId = groupId,
        groupName = groupName
    )
}

private fun NotificationStyle.toPayload(): NotificationStylePayload {
    return when (this) {
        NotificationStyle.Default -> NotificationStylePayload.Default
        is NotificationStyle.BigText -> NotificationStylePayload.BigText(bigText, summaryText, bigContentTitle)
        is NotificationStyle.Inbox -> NotificationStylePayload.Inbox(lines, summaryText, bigContentTitle)
        is NotificationStyle.BigPicture -> NotificationStylePayload.BigPicture(
            pictureResId,
            pictureUriString,
            summaryText,
            bigContentTitle,
            largeIconResId,
            hideExpandedLargeIcon
        )
        is NotificationStyle.Messaging -> NotificationStylePayload.Messaging(
            userDisplayName = userDisplayName,
            messages = messages.map { NotificationMessagePayload(it.text, it.timestampMillis, it.senderName) },
            conversationTitle = conversationTitle,
            isGroupConversation = isGroupConversation
        )
        is NotificationStyle.Media -> NotificationStylePayload.Media(compactActionIndices)
        is NotificationStyle.DecoratedCustomView -> NotificationStylePayload.DecoratedCustomView(customView.toPayload())
        is NotificationStyle.DecoratedMediaCustomView -> NotificationStylePayload.DecoratedMediaCustomView(
            customView = customView.toPayload(),
            compactActionIndices = compactActionIndices
        )
        is NotificationStyle.Call -> NotificationStylePayload.Call(
            callType = callType,
            person = person.toPayload(),
            isVideo = isVideo,
            verificationText = verificationText
        )
    }
}

private fun NotificationStylePayload.toDomain(): NotificationStyle {
    return when (this) {
        NotificationStylePayload.Default -> NotificationStyle.Default
        is NotificationStylePayload.BigText -> NotificationStyle.BigText(bigText, summaryText, bigContentTitle)
        is NotificationStylePayload.Inbox -> NotificationStyle.Inbox(lines, summaryText, bigContentTitle)
        is NotificationStylePayload.BigPicture -> NotificationStyle.BigPicture(
            pictureResId,
            pictureUriString,
            summaryText,
            bigContentTitle,
            largeIconResId,
            hideExpandedLargeIcon
        )
        is NotificationStylePayload.Messaging -> NotificationStyle.Messaging(
            userDisplayName = userDisplayName,
            messages = messages.map { NotificationMessage(it.text, it.timestampMillis, it.senderName) },
            conversationTitle = conversationTitle,
            isGroupConversation = isGroupConversation
        )
        is NotificationStylePayload.Media -> NotificationStyle.Media(compactActionIndices)
        is NotificationStylePayload.DecoratedCustomView -> NotificationStyle.DecoratedCustomView(customView.toDomain())
        is NotificationStylePayload.DecoratedMediaCustomView -> NotificationStyle.DecoratedMediaCustomView(
            customView = customView.toDomain(),
            compactActionIndices = compactActionIndices
        )
        is NotificationStylePayload.Call -> NotificationStyle.Call(
            callType = callType,
            person = person.toDomain(),
            isVideo = isVideo,
            verificationText = verificationText
        )
    }
}

private fun NotificationCustomViewStyleData.toPayload(): NotificationCustomViewStyleDataPayload {
    return NotificationCustomViewStyleDataPayload(
        layoutResId = layoutResId,
        bigLayoutResId = bigLayoutResId,
        titleViewId = titleViewId,
        titleText = titleText,
        messageViewId = messageViewId,
        messageText = messageText,
        iconViewId = iconViewId,
        iconResId = iconResId
    )
}

private fun NotificationCustomViewStyleDataPayload.toDomain(): NotificationCustomViewStyleData {
    return NotificationCustomViewStyleData(
        layoutResId = layoutResId,
        bigLayoutResId = bigLayoutResId,
        titleViewId = titleViewId,
        titleText = titleText,
        messageViewId = messageViewId,
        messageText = messageText,
        iconViewId = iconViewId,
        iconResId = iconResId
    )
}

private fun NotificationCallPerson.toPayload(): NotificationCallPersonPayload {
    return NotificationCallPersonPayload(
        name = name,
        avatarResId = avatarResId
    )
}

private fun NotificationCallPersonPayload.toDomain(): NotificationCallPerson {
    return NotificationCallPerson(
        name = name,
        avatarResId = avatarResId
    )
}
