package com.ahnc

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.annotation.RequiresPermission
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import com.ahnc.ui.DebugConsole
import com.ahnc.ui.DebugMessageType
import com.ahnc.ui.HandlePermissions
import com.ahnc.ui.PermissionDialogView
import com.ahnc.ui.theme.AhncTheme
import com.ahnc.ui.tryLog

class MainActivity : ComponentActivity() {
    private var permissions = arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.NEARBY_WIFI_DEVICES,
    )

    private val permissionDialog by viewModels<PermissionDialogView>()

    private lateinit var wifiDirectManager: WifiDirectManager
    private lateinit var wifiDirectBroadcastReceiver : WifiDirectBroadcastReceiver

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        tryLog(DebugMessageType.Error) {
            this.wifiDirectManager = WifiDirectManager(this)
        }

        this.showUi()
    }

    override fun onDestroy() {
        super.onDestroy()
        DebugConsole.clear()
    }

    override fun onResume() {
        super.onResume()

        tryLog(DebugMessageType.Error) {
            this.wifiDirectBroadcastReceiver = WifiDirectBroadcastReceiver()
        }

        ContextCompat.registerReceiver(
            this,
            this.wifiDirectBroadcastReceiver,
            this.wifiDirectManager.intentFilter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onPause() {
        super.onPause()
        this.unregisterReceiver(this.wifiDirectBroadcastReceiver)
    }

    fun showUi() {
        setContent {
            AhncTheme {
                HandlePermissions(this, this.permissions, this.permissionDialog)

                Column(
                    modifier = Modifier.fillMaxSize()
                ) {
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(0.5f)
                            .background(Color.Red)
                    ) {
                        Button({
                            DebugConsole.log(DebugMessageType.Warn, "Test")
                        }) {
                            Text("Warn")
                        }
                    }
                    DebugConsole.Compose()
                }
            }
        }
    }
}

class WifiDirectManager(context: Context) {
    val intentFilter = IntentFilter()
    private var manager: WifiP2pManager
    private var channel: WifiP2pManager.Channel

    init {
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)

        this.manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
        this.channel = this.manager.initialize(context, context.mainLooper, null)
    }

    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    // TODO!
    fun discoverPeers(listener: WifiP2pManager.ActionListener) {
        this.manager.discoverPeers(this.channel, listener)
    }
}

class WifiDirectBroadcastReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when(intent.action) {
            WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                val wifiEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                DebugConsole.log(DebugMessageType.Info, "WifiP2p changed.")
                DebugConsole.log(DebugMessageType.Info, "WifiP2p is enabled: ${wifiEnabled}.")
            }
            WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                DebugConsole.log(DebugMessageType.Info, "WifiP2p peers changed.")
            }
            WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                DebugConsole.log(DebugMessageType.Info, "WifiP2p connection changed.")
            }
            WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                DebugConsole.log(DebugMessageType.Info, "WifiP2p this device changed.")
            }
        }
    }
}
