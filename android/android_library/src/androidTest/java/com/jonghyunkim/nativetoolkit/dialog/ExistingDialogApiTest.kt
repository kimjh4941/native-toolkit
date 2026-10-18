package com.jonghyunkim.nativetoolkit.dialog

import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.testing.TestFragmentActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

// IT-23 of the Kotlin API design (dialog part): AndroidDialogFragment's factories and listeners,
// used as the sample used them until stage 1b, give the results the stage 0c UI tests expected
// (DialogUiTest d01 to d16 before the sample moved to AndroidDialogManager). A fragment made by
// newInstance has no request ID, so the library's request handling stays out (RK-07).
@RunWith(AndroidJUnit4::class)
class ExistingDialogApiTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private lateinit var scenario: ActivityScenario<TestFragmentActivity>
    private val results = LinkedBlockingQueue<String>()

    @Before
    fun setUp() {
        scenario = ActivityScenario.launch(TestFragmentActivity::class.java)
        device.wait(Until.hasObject(By.text(TestFragmentActivity::class.java.simpleName)), 5_000)
    }

    @After
    fun tearDown() {
        scenario.close()
    }

    // The results in the sample's format: "<listener> - <values>" with isSuccessful.
    private fun show(fragment: AndroidDialogFragment, title: String) {
        scenario.onActivity { fragment.show(it.supportFragmentManager, "it23") }
        assertNotNull("'$title' did not appear", device.wait(Until.findObject(By.text(title)), 5_000))
        device.waitForIdle()
    }

    private fun alert() = AndroidDialogFragment.newInstance(
        title = "Hello from Android", message = "This is a native Android dialog!", buttonText = "OK",
        cancelableOnTouchOutside = false, cancelable = false
    ).apply {
        setDialogListener(object : AndroidDialogFragment.DialogListener {
            override fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                results.add("$isSuccessful onDialog - buttonText: $buttonText, errorMessage: $errorMessage")
            }
        })
    }

    private fun confirm() = AndroidDialogFragment.newInstance(
        title = "Confirmation", message = "Do you want to proceed with this action?",
        negativeButtonText = "No", positiveButtonText = "Yes", cancelableOnTouchOutside = false, cancelable = false
    ).apply {
        setConfirmDialogListener(object : AndroidDialogFragment.ConfirmDialogListener {
            override fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                results.add("$isSuccessful onConfirmDialog - buttonText: $buttonText, errorMessage: $errorMessage")
            }
        })
    }

    private fun singleChoice() = AndroidDialogFragment.newInstance(
        title = "Please select one", singleChoiceItems = arrayOf("Option 1", "Option 2", "Option 3"), checkedItem = 0,
        negativeButtonText = "Cancel", positiveButtonText = "OK", cancelableOnTouchOutside = false, cancelable = false
    ).apply {
        setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
            override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?) {
                results.add("$isSuccessful onSingleChoiceItemDialog - buttonText: $buttonText, checkedItem: $checkedItem, errorMessage: $errorMessage")
            }
        })
    }

    private fun multiChoice() = AndroidDialogFragment.newInstance(
        title = "Multiple Selection", multiChoiceItems = arrayOf("Option 1", "Option 2", "Option 3", "Option 4"),
        checkedItems = booleanArrayOf(false, true, false, true), negativeButtonText = "Cancel", positiveButtonText = "OK",
        cancelableOnTouchOutside = false, cancelable = false
    ).apply {
        setMultiChoiceItemDialogListener(object : AndroidDialogFragment.MultiChoiceItemDialogListener {
            override fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?) {
                results.add("$isSuccessful onMultiChoiceItemDialog - buttonText: $buttonText, checkedItems: ${checkedItems.contentToString()}, errorMessage: $errorMessage")
            }
        })
    }

    private fun textInput() = AndroidDialogFragment.newInstance(
        title = "Text Input", message = "Please enter your name", hint = "Enter here...", negativeButtonText = "Cancel",
        positiveButtonText = "OK", enablePositiveButtonWhenEmpty = false, cancelableOnTouchOutside = false, cancelable = false
    ).apply {
        setTextInputDialogListener(object : AndroidDialogFragment.TextInputDialogListener {
            override fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?) {
                results.add("$isSuccessful onTextInputDialog - buttonText: $buttonText, inputText: $inputText, errorMessage: $errorMessage")
            }
        })
    }

    private fun login() = AndroidDialogFragment.newInstance(
        title = "Login", message = "Please enter your credentials", usernameHint = "Username", passwordHint = "Password",
        negativeButtonText = "Cancel", positiveButtonText = "Login", enablePositiveButtonWhenEmpty = false,
        cancelableOnTouchOutside = false, cancelable = false
    ).apply {
        setLoginDialogListener(object : AndroidDialogFragment.LoginDialogListener {
            override fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?) {
                results.add("$isSuccessful onLoginDialog - buttonText: $buttonText, username: $username, password: $password, errorMessage: $errorMessage")
            }
        })
    }

    // The positive (button1) or negative (button2) button with [label]; the platform theme may
    // show labels in capitals.
    private fun button(label: String): UiObject2 {
        val pattern = Pattern.compile(Pattern.quote(label), Pattern.CASE_INSENSITIVE)
        return listOf("button1", "button2").firstNotNullOfOrNull { device.findObject(By.res("android", it).text(pattern)) }
            ?: throw AssertionError("no button '$label'")
    }

    // Hint text and password flag of each text field, from the accessibility nodes.
    private fun inputInfo(): List<Pair<String?, Boolean>> {
        val result = mutableListOf<Pair<String?, Boolean>>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        instrumentation.uiAutomation.rootInActiveWindow?.let(queue::add)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.className?.toString() == "android.widget.EditText") result += node.hintText?.toString() to node.isPassword
            for (i in 0 until node.childCount) node.getChild(i)?.let(queue::add)
        }
        return result
    }

    private fun tapOutside() {
        device.click(device.displayWidth / 2, device.displayHeight / 12)
        device.waitForIdle()
    }

    private fun isChecked(item: String) = device.findObject(By.text(item)).isChecked

    private fun inputs() = device.findObjects(By.clazz("android.widget.EditText")).sortedBy { it.visibleBounds.top }

    private fun expect(result: String) = assertEquals(result, results.poll(10, TimeUnit.SECONDS))

    @Test
    fun alertAndConfirm_d01_d02_d03() {
        show(alert(), "Hello from Android")
        button("OK").click()
        expect("true onDialog - buttonText: OK, errorMessage: null")

        show(confirm(), "Confirmation")
        button("Yes").click()
        expect("true onConfirmDialog - buttonText: Yes, errorMessage: null")

        show(confirm(), "Confirmation")
        button("No").click()
        expect("true onConfirmDialog - buttonText: No, errorMessage: null")
    }

    @Test
    fun singleChoice_d04_d05_d06() {
        show(singleChoice(), "Please select one")
        assertEquals(listOf(true, false, false), (1..3).map { isChecked("Option $it") })
        button("OK").click()
        expect("true onSingleChoiceItemDialog - buttonText: OK, checkedItem: 0, errorMessage: null")

        show(singleChoice(), "Please select one")
        device.findObject(By.text("Option 3")).click()
        device.wait(Until.hasObject(By.text("Option 3").checked(true)), 2_000)
        button("OK").click()
        expect("true onSingleChoiceItemDialog - buttonText: OK, checkedItem: 2, errorMessage: null")

        show(singleChoice(), "Please select one")
        button("Cancel").click()
        expect("true onSingleChoiceItemDialog - buttonText: Cancel, checkedItem: null, errorMessage: null")
    }

    @Test
    fun multiChoice_d07_d08_d09() {
        show(multiChoice(), "Multiple Selection")
        assertEquals(listOf(false, true, false, true), (1..4).map { isChecked("Option $it") })
        button("OK").click()
        expect("true onMultiChoiceItemDialog - buttonText: OK, checkedItems: [false, true, false, true], errorMessage: null")

        show(multiChoice(), "Multiple Selection")
        device.findObject(By.text("Option 1")).click()
        device.wait(Until.hasObject(By.text("Option 1").checked(true)), 2_000)
        button("OK").click()
        expect("true onMultiChoiceItemDialog - buttonText: OK, checkedItems: [true, true, false, true], errorMessage: null")

        show(multiChoice(), "Multiple Selection")
        button("Cancel").click()
        expect("true onMultiChoiceItemDialog - buttonText: Cancel, checkedItems: null, errorMessage: null")
    }

    @Test
    fun textInput_d10_d11_d12() {
        show(textInput(), "Text Input")
        assertNotNull(device.findObject(By.text("Please enter your name")))
        assertEquals(listOf("Enter here..." to false), inputInfo())
        assertFalse(button("OK").isEnabled)
        inputs().single().text = "Alice"
        device.waitForIdle()
        button("OK").click()
        expect("true onTextInputDialog - buttonText: OK, inputText: Alice, errorMessage: null")

        show(textInput(), "Text Input")
        button("Cancel").click()
        expect("true onTextInputDialog - buttonText: Cancel, inputText: null, errorMessage: null")
    }

    @Test
    fun login_d13_d14_d15() {
        show(login(), "Login")
        assertNotNull(device.findObject(By.text("Please enter your credentials")))
        assertEquals(listOf("Username" to false, "Password" to true), inputInfo())
        assertFalse(button("Login").isEnabled)
        inputs()[0].text = "user1"
        device.waitForIdle()
        assertFalse(button("Login").isEnabled)
        inputs()[1].text = "pass1"
        device.waitForIdle()
        button("Login").click()
        expect("true onLoginDialog - buttonText: Login, username: user1, password: pass1, errorMessage: null")

        show(login(), "Login")
        button("Cancel").click()
        expect("true onLoginDialog - buttonText: Cancel, username: null, password: null, errorMessage: null")
    }

    @Test
    fun backAndOutsideTap_doNotCloseANonCancelableDialog_d16() {
        val cases = listOf(
            alert() to "Hello from Android", confirm() to "Confirmation", singleChoice() to "Please select one",
            multiChoice() to "Multiple Selection", textInput() to "Text Input", login() to "Login"
        )
        for ((fragment, title) in cases) {
            show(fragment, title)
            device.pressBack()
            device.waitForIdle()
            assertTrue("$title closed on Back", device.hasObject(By.text(title)))
            tapOutside()
            assertTrue("$title closed on an outside tap", device.hasObject(By.text(title)))
            button(if (title == "Hello from Android") "OK" else if (title == "Confirmation") "No" else "Cancel").click()
            assertNotNull("no result for $title", results.poll(10, TimeUnit.SECONDS))
        }
    }
}
