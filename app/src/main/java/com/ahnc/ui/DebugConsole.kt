package com.ahnc.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp

enum class DebugMessageType {
    Debug,
    Info,
    Warn,
    Error,
}

class DebugMessage(val type: DebugMessageType, val msg: String)

/**
 * This is a singleton class, made to display logs inside the application itself.
 */
class DebugConsole private constructor() {
    companion object {
        @Volatile
        private var instance: DebugConsole? = null

        private fun get(): DebugConsole {
            return this.instance ?: synchronized(this) {
                this.instance ?: DebugConsole().also { this.instance = it }
            }
        }

        fun log(type: DebugMessageType, msg: String) {
            this.get().messages.add(DebugMessage(type, msg))
        }

        fun clear() {
            this.get().messages.clear()
        }

        // This is the ui.
        @Composable
        fun Compose() {
            val scrollState = rememberScrollState()
            val messages = this.get().messages

            LaunchedEffect(messages.size) {
                scrollState.animateScrollTo(scrollState.maxValue)
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.3f)
                    .background(Color.LightGray)
                    .padding(
                        vertical = Dp(5f),
                        horizontal = Dp(2f)
                    )
                    .verticalScroll(scrollState),
                verticalArrangement = Arrangement.spacedBy(Dp(2f))
            ) {
                messages.forEach { msg ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Color.Gray),
                        horizontalArrangement = Arrangement.Absolute.Left,
                    ) {
                        when (msg.type) {
                            DebugMessageType.Debug -> Text("Debug: ", color = Color.Blue)
                            DebugMessageType.Info -> Text("Info: ", color = Color.Green)
                            DebugMessageType.Warn -> Text("Warn: ", color = Color.Yellow)
                            DebugMessageType.Error -> Text("Error: ", color = Color.Red)
                        }

                        Text(msg.msg)
                    }
                }
            }
        }
    }

    private var messages = mutableStateListOf<DebugMessage>()
}

/**
 * try / catch(e: Exception), that logs the Exception as a DebugMessage, with type specified.
 */
fun<T> tryLog(type: DebugMessageType, action: () -> T) {
    try {
        action()
    } catch (e: Exception) {
        DebugConsole.log(type, "$e")
    }
}

fun logInfo(msg: String) {
    DebugConsole.log(DebugMessageType.Info, msg)
}
fun logDebug(msg: String) {
    DebugConsole.log(DebugMessageType.Debug, msg)
}
fun logWarn(msg: String) {
    DebugConsole.log(DebugMessageType.Warn, msg)
}
fun logError(msg: String) {
    DebugConsole.log(DebugMessageType.Error, msg)
}
