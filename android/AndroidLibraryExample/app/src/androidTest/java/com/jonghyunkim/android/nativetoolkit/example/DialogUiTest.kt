package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryDialog
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Dialog screen (6.2 of the android-c-abi UI test design). */
@CategoryDialog
@RunWith(AndroidJUnit4::class)
class DialogUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("dialog")
    }

    @Test
    fun d01_alertOk() {
        app.click("dialog.showDialog")
        dialogs.waitFor("Hello from Android")
        assertEquals("This is a native Android dialog!", dialogs.message())
        assertButton("OK", dialogs.positive().text)
        dialogs.positive().click()
        expectResult("onDialog - buttonText: OK, errorMessage: null")
    }

    @Test
    fun d02_confirmYes() {
        app.click("dialog.showConfirmDialog")
        dialogs.waitFor("Confirmation")
        assertEquals("Do you want to proceed with this action?", dialogs.message())
        assertButton("No", dialogs.negative().text)
        assertButton("Yes", dialogs.positive().text)
        dialogs.positive().click()
        expectResult("onConfirmDialog - buttonText: Yes, errorMessage: null")
    }

    @Test
    fun d03_confirmNo() {
        app.click("dialog.showConfirmDialog")
        dialogs.waitFor("Confirmation")
        dialogs.negative().click()
        expectResult("onConfirmDialog - buttonText: No, errorMessage: null")
    }

    @Test
    fun d04_singleChoiceDefault() {
        app.click("dialog.showSingleChoiceItemDialog")
        dialogs.waitFor("Please select one")
        assertTrue(dialogs.isChecked("Option 1"))
        assertFalse(dialogs.isChecked("Option 2"))
        assertFalse(dialogs.isChecked("Option 3"))
        dialogs.positive().click()
        expectResult("onSingleChoiceItemDialog - buttonText: OK, checkedItem: 0, errorMessage: null")
    }

    @Test
    fun d05_singleChoiceThird() {
        app.click("dialog.showSingleChoiceItemDialog")
        dialogs.waitFor("Please select one")
        dialogs.clickItem("Option 3")
        dialogs.positive().click()
        expectResult("onSingleChoiceItemDialog - buttonText: OK, checkedItem: 2, errorMessage: null")
    }

    @Test
    fun d06_singleChoiceCancel() {
        app.click("dialog.showSingleChoiceItemDialog")
        dialogs.waitFor("Please select one")
        dialogs.negative().click()
        expectResult("onSingleChoiceItemDialog - buttonText: Cancel, checkedItem: null, errorMessage: null")
    }

    @Test
    fun d07_multiChoiceDefault() {
        app.click("dialog.showMultiChoiceItemDialog")
        dialogs.waitFor("Multiple Selection")
        assertEquals(listOf(false, true, false, true), (1..4).map { dialogs.isChecked("Option $it") })
        dialogs.positive().click()
        expectResult("onMultiChoiceItemDialog - buttonText: OK, checkedItems: [false, true, false, true], errorMessage: null")
    }

    @Test
    fun d08_multiChoiceCheckFirst() {
        app.click("dialog.showMultiChoiceItemDialog")
        dialogs.waitFor("Multiple Selection")
        dialogs.clickItem("Option 1")
        dialogs.positive().click()
        expectResult("onMultiChoiceItemDialog - buttonText: OK, checkedItems: [true, true, false, true], errorMessage: null")
    }

    @Test
    fun d09_multiChoiceCancel() {
        app.click("dialog.showMultiChoiceItemDialog")
        dialogs.waitFor("Multiple Selection")
        dialogs.negative().click()
        expectResult("onMultiChoiceItemDialog - buttonText: Cancel, checkedItems: null, errorMessage: null")
    }

    @Test
    fun d10_textInputShowsHintAndDisablesOkWhileEmpty() {
        app.click("dialog.showTextInputDialog")
        dialogs.waitFor("Text Input")
        assertEquals("Please enter your name", dialogs.message())
        assertEquals(listOf("Enter here..." to false), dialogs.inputInfo())
        assertFalse(dialogs.positive().isEnabled)
        dialogs.negative().click()
    }

    @Test
    fun d11_textInputOk() {
        app.click("dialog.showTextInputDialog")
        dialogs.waitFor("Text Input")
        dialogs.inputs()[0].text = "Alice"
        device.waitForIdle()
        dialogs.positive().click()
        expectResult("onTextInputDialog - buttonText: OK, inputText: Alice, errorMessage: null")
    }

    @Test
    fun d12_textInputCancel() {
        app.click("dialog.showTextInputDialog")
        dialogs.waitFor("Text Input")
        dialogs.negative().click()
        expectResult("onTextInputDialog - buttonText: Cancel, inputText: null, errorMessage: null")
    }

    @Test
    fun d13_loginShowsHintsMasksPasswordAndNeedsBothFields() {
        app.click("dialog.showLoginDialog")
        dialogs.waitFor("Login")
        assertEquals("Please enter your credentials", dialogs.message())
        assertEquals(listOf("Username" to false, "Password" to true), dialogs.inputInfo())
        assertFalse(dialogs.positive().isEnabled)
        dialogs.inputs()[0].text = "user1"
        device.waitForIdle()
        assertFalse(dialogs.positive().isEnabled)
        dialogs.negative().click()
    }

    @Test
    fun d14_loginOk() {
        app.click("dialog.showLoginDialog")
        dialogs.waitFor("Login")
        val inputs = dialogs.inputs()
        inputs[0].text = "user1"
        inputs[1].text = "pass1"
        device.waitForIdle()
        dialogs.positive().click()
        expectResult("onLoginDialog - buttonText: Login, username: user1, password: pass1, errorMessage: null")
    }

    @Test
    fun d15_loginCancel() {
        app.click("dialog.showLoginDialog")
        dialogs.waitFor("Login")
        dialogs.negative().click()
        expectResult("onLoginDialog - buttonText: Cancel, username: null, password: null, errorMessage: null")
    }

    @Test
    fun d16_backAndOutsideTapDoNotCloseAnyDialog() {
        val cases = listOf(
            "dialog.showDialog" to "Hello from Android",
            "dialog.showConfirmDialog" to "Confirmation",
            "dialog.showSingleChoiceItemDialog" to "Please select one",
            "dialog.showMultiChoiceItemDialog" to "Multiple Selection",
            "dialog.showTextInputDialog" to "Text Input",
            "dialog.showLoginDialog" to "Login"
        )
        for ((tag, title) in cases) {
            app.click(tag)
            dialogs.waitFor(title)
            device.pressBack()
            device.waitForIdle()
            assertTrue("$title closed on Back", dialogs.isShowing())
            dialogs.tapOutside()
            assertTrue("$title closed on an outside tap", dialogs.isShowing())
            if (tag == "dialog.showDialog") dialogs.positive().click() else dialogs.negative().click()
            device.waitForIdle()
        }
    }

    /** The platform theme shows button labels in capitals, so compare them ignoring case. */
    private fun assertButton(expected: String, actual: String?) {
        assertTrue("button <$actual> is not <$expected>", expected.equals(actual, ignoreCase = true))
    }

    private fun expectResult(result: String) {
        app.waitForStatus("dialog", "✅\nResult: $result")
    }
}
