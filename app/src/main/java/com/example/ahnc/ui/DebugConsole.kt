package com.example.ahnc.ui

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
    Info,
    Warn,
    Error,
}

class DebugMessage(public val type: DebugMessageType, public val msg: String) {}

class DebugConsole private constructor() {
    companion object {
        @Volatile
        private var instance: DebugConsole? = null

        fun get(): DebugConsole {
            return this.instance ?: synchronized(this) {
                this.instance ?: DebugConsole().also { this.instance = it }
            }
        }
    }

    private var messages = mutableStateListOf<DebugMessage>()

    @Composable
    fun Compose() {
        val scrollState = rememberScrollState()

        LaunchedEffect(this.messages.size) {
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
            this@DebugConsole.messages.forEach { msg ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.Gray),
                    horizontalArrangement = Arrangement.Absolute.Left,
                ) {
                    when (msg.type) {
                        DebugMessageType.Info -> Text("Info: ", color = Color.Green)
                        DebugMessageType.Warn -> Text("Warn: ", color = Color.Yellow)
                        DebugMessageType.Error -> Text("Error", color = Color.Red)
                    }

                    Text(msg.msg)
                }
            }
        }
    }

    fun push(type: DebugMessageType, msg: String) {
        this.messages.add(DebugMessage(type, msg))
    }
}