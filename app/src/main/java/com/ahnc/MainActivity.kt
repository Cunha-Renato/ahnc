package com.ahnc

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.annotation.RequiresPermission
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ahnc.ui.DebugConsole
import com.ahnc.ui.DebugMessageType
import com.ahnc.ui.HandlePermissions
import com.ahnc.ui.PermissionDialogView
import com.ahnc.ui.logDebug
import com.ahnc.ui.logError
import com.ahnc.ui.logInfo
import com.ahnc.ui.theme.AhncTheme
import com.ahnc.ui.tryLog

class MainActivity : ComponentActivity() {
    private var permissions: Array<String>

    private val ahnc = AhncCore()
    private val permissionDialog by viewModels<PermissionDialogView>()

    init {
        if (Build.VERSION.SDK_INT >= 33) {
            this.permissions = arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.NEARBY_WIFI_DEVICES,
            )
        } else {
            this.permissions = arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        }
    }

    fun hasPermissions(): Boolean {
        this.permissions.forEach { permission ->
            if (ActivityCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }

        return true
    }

    @SuppressLint("MissingPermission")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        this.ahnc.onCreate(this)
        this.showUi()
    }

    override fun onDestroy() {
        super.onDestroy()
        DebugConsole.clear()
    }

    override fun onResume() {
        super.onResume()
        this.ahnc.registerReceiver()
    }

    override fun onPause() {
        super.onPause()
        this.ahnc.unregisterReceiver()
    }

    @SuppressLint("MissingPermission")
    fun showUi() {
        setContent {
            AhncTheme {
                HandlePermissions(this, this.permissions, this.permissionDialog)

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(WindowInsets.safeDrawing.asPaddingValues())
                ) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .padding(all = Dp(15f))
                    ) {
                        Button({
                            if (this@MainActivity.hasPermissions()) {
                                this@MainActivity.ahnc.initiatePeersDiscovery()
                            }
                        }) {
                            Text("Init Peer Discovery")
                        }

                        Button({
                            DebugConsole.clear()
                        }) {
                            Text("Clear Console")
                        }
                    }

                    DebugConsole.Compose()
                }
            }
        }
    }
}

class AhncCore {
    private lateinit var activity: MainActivity
    private lateinit var wifiManager: WifiDirectManager
    private lateinit var wifiBroadcastReceiver: WifiDirectBroadcastReceiver

    fun onCreate(activity: MainActivity) {
        tryLog(DebugMessageType.Error) {
            this.activity = activity
            this.wifiManager = WifiDirectManager(this.activity)
        }
    }

    fun registerReceiver() {
        tryLog(DebugMessageType.Error) {
            this.wifiBroadcastReceiver = WifiDirectBroadcastReceiver(this.wifiManager)

            ContextCompat.registerReceiver(
                this.activity,
                this.wifiBroadcastReceiver,
                this.wifiManager.intentFilter,
                ContextCompat.RECEIVER_EXPORTED
            )
        }
    }

    fun unregisterReceiver() {
        tryLog(DebugMessageType.Error) {
            this.activity.unregisterReceiver(this.wifiBroadcastReceiver)
        }
    }

    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.NEARBY_WIFI_DEVICES])
    fun initiatePeersDiscovery() {
        tryLog(DebugMessageType.Error) {
            this.wifiManager.discoverPeers(object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    logInfo("Peers discovery initialized.")
                }

                override fun onFailure(reason: Int) {
                    var reasonStr = "Unknown"
                    when(reason) {
                        WifiP2pManager.P2P_UNSUPPORTED -> {
                            reasonStr = "P2P_UNSUPPORTED"
                        }
                        WifiP2pManager.ERROR -> {
                            reasonStr = "INTERNAL_ERROR"
                        }
                        WifiP2pManager.BUSY -> {
                            reasonStr = "BUSY"
                        }
                    }

                    logError("Peers discovery failed, reason: $reasonStr. Try again...")
                }
            })
        }
    }
}

class WifiDirectManager(context: Context) {
    val intentFilter = IntentFilter()
    var inner: WifiP2pManager
    private var channel: WifiP2pManager.Channel
    private val peers = mutableListOf<WifiP2pDevice>()
    private val peersListListener = WifiP2pManager.PeerListListener { peerList ->
        val refreshedPeers = peerList.deviceList
        if (refreshedPeers != this.peers) {
            this.peers.clear()
            peers.addAll(refreshedPeers)
        }

        if (this.peers.isEmpty()) {
            logDebug("No peers found.")
            return@PeerListListener
        }

        this.peers.forEach { peer ->
            logDebug("Peer: $peer.")
        }
    }

    init {
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        this.intentFilter.addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)

        this.inner = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
        this.channel = this.inner.initialize(context, context.mainLooper, null)
    }

    @RequiresPermission(
        allOf = [Manifest.permission.NEARBY_WIFI_DEVICES, Manifest.permission.ACCESS_FINE_LOCATION
        ], conditional = true
    )
    fun discoverPeers(listener: WifiP2pManager.ActionListener) {
        this.inner.discoverPeers(this.channel, listener)
    }

    @RequiresPermission(
        allOf = [Manifest.permission.NEARBY_WIFI_DEVICES, Manifest.permission.ACCESS_FINE_LOCATION
        ], conditional = true
    )
    fun requestPeers() {
        this.inner.requestPeers(this.channel, this.peersListListener)
    }
}

class WifiDirectBroadcastReceiver(private val manager: WifiDirectManager): BroadcastReceiver() {
    @SuppressLint("MissingPermission")
    override fun onReceive(context: Context, intent: Intent) {
        tryLog(DebugMessageType.Error) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    val wifiEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    DebugConsole.log(DebugMessageType.Info, "WifiP2p changed.")
                    DebugConsole.log(DebugMessageType.Info, "WifiP2p is enabled: ${wifiEnabled}.")
                }

                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    DebugConsole.log(DebugMessageType.Info, "WifiP2p peers changed.")
                    this.manager.requestPeers()
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
}