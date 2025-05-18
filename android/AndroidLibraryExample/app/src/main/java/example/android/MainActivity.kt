package example.android

import android.library.dialog.AndroidDialogFragment
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import example.android.ui.theme.AndroidTheme

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AndroidTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Button(onClick = {
                            Log.d(TAG, "onClick")
                            val dialog = AndroidDialogFragment.newInstance(
                                "タイトル",
                                "宜しくお願い致します。"
                            ).apply {
                                setAndroidDialogListener(object :
                                    AndroidDialogFragment.AndroidDialogListener {
                                    override fun onClickDialogNeutralButton(dialog: AndroidDialogFragment) {
                                        Log.d(TAG, "onClickDialogNeutralButton")
                                    }

                                    override fun onClickDialogNegativeButton(dialog: AndroidDialogFragment) {
                                        Log.d(TAG, "onClickDialogNegativeButton")
                                    }

                                    override fun onClickDialogPositiveButton(dialog: AndroidDialogFragment) {
                                        Log.d(TAG, "onClickDialogPositiveButton")
                                    }
                                })
                            }
                            dialog.show(
                                supportFragmentManager, "NativeDialogFragment"
                            )
                        }) {
                            Text(text = "ダイアログを表示")
                        }
                    }
                }
            }
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(
        text = "Hello $name!",
        modifier = modifier
    )
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
    AndroidTheme {
        Greeting("Android")
    }
}