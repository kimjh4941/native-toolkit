package com.jonghyunkim.android.nativetoolkit.example.infra

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction

/**
 * Drives the sample's Compose screens by test tag (section 3.6 of the UI test design).
 *
 * Screen names are the tag prefixes: `dialog`, `notification`, `share`, `clipboard`, `receivedShare`.
 */
class SampleApp(private val rule: ComposeTestRule) {

    /** Opens a screen from the main menu (`menu.<screen>`). */
    fun open(screen: String) {
        scrollTo("menu.$screen")
        rule.onNodeWithTag("menu.$screen").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
        rule.waitUntil(TIMEOUT_MS) { exists("$screen.back") }
    }

    /**
     * Clicks the node with [tag], scrolling the screen's lazy list to it first when needed.
     *
     * The click runs the node's OnClick semantics action instead of injecting a touch: a touch
     * lands by screen position and hit the button above the target after the shade closed or the
     * status text above the list changed its height.
     */
    fun click(tag: String) {
        scrollTo(tag)
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
    }

    /** Returns the text of the node with [tag]. */
    fun text(tag: String): String {
        scrollTo(tag)
        val node = rule.onNodeWithTag(tag).fetchSemanticsNode()
        return node.config.getOrNull(SemanticsProperties.Text)?.joinToString("") { it.text }.orEmpty()
    }

    /** Returns the status text of [screen] (`<screen>.status`). */
    fun status(screen: String): String = text("$screen.status")

    /** Waits until the status text of [screen] contains [expected], and returns it. */
    fun waitForStatus(screen: String, expected: String, timeoutMs: Long = TIMEOUT_MS): String {
        try {
            rule.waitUntil(timeoutMs) { status(screen).contains(expected) }
        } catch (e: Throwable) {
            throw AssertionError("status of $screen did not contain <$expected> within $timeoutMs ms; was <${status(screen)}>", e)
        }
        return status(screen)
    }

    /** Waits until the node with [tag] shows exactly [expected]. */
    fun waitForText(tag: String, expected: String, timeoutMs: Long = TIMEOUT_MS) {
        try {
            rule.waitUntil(timeoutMs) { exists(tag) && text(tag) == expected }
        } catch (e: Throwable) {
            throw AssertionError("$tag did not show <$expected> within $timeoutMs ms; was <${if (exists(tag)) text(tag) else "(missing)"}>", e)
        }
    }

    /** Whether a node with [tag] is currently composed. */
    fun exists(tag: String): Boolean = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    /** Goes back to the main menu with the screen's back button. */
    fun back(screen: String) {
        click("$screen.back")
        rule.waitUntil(TIMEOUT_MS) { exists("menu.dialog") }
    }

    private fun scrollTo(tag: String) {
        if (exists(tag)) return
        rule.onNode(hasScrollAction()).performScrollToNode(hasTestTag(tag))
    }

    companion object {
        const val TIMEOUT_MS = 10_000L
    }
}
