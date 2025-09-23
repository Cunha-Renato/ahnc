package com.ahnc.ui

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.AlertDialogDefaults
import androidx.compose.material3.BasicAlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

class PermissionDialogView: ViewModel() {
    private var showDialog = MutableStateFlow(false)
    private var launchAppSettings = MutableStateFlow(false)

    @Composable
    fun getShowDialog(): Boolean = this.showDialog.collectAsState().value

    @Composable
    fun getLaunchAppSettings(): Boolean = this.launchAppSettings.collectAsState().value

    fun setShowDialog(value: Boolean) {
        this.showDialog.update { value }
    }

    fun setLaunchAppSettings(value: Boolean) {
        this.launchAppSettings.update { value }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Compose(
        onGranted: () -> Unit,
    ) {
        BasicAlertDialog(
            modifier = Modifier.width(Dp(300f)),
            onDismissRequest = {
                this.setShowDialog(false)
            },
            properties = DialogProperties()
        ) {
            Surface(
                modifier = Modifier.wrapContentWidth().wrapContentHeight(),
                shape = MaterialTheme.shapes.large,
                tonalElevation = AlertDialogDefaults.TonalElevation
            ) {
                Column(modifier = Modifier.padding(Dp(16f))) {
                    Text(
                        text = "Permissions are needed",
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "This app cannot function without the permissions.",
                    )
                    Spacer(modifier = Modifier.height(Dp(24f)))
                    TextButton(
                        onClick = onGranted,
                        modifier = Modifier.align(Alignment.End)
                    ) {
                        Text("Confirm")
                    }
                }
            }
        }
    }
}

@Composable
fun HandlePermissions(
    activity: Activity,
    permissions: Array<String>,
    dialog: PermissionDialogView,
) {
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
        onResult = { result ->
            permissions.forEach { permission ->
                if (result[permission] == false) {
                    if (!activity.shouldShowRequestPermissionRationale(permission)) {
                        dialog.setLaunchAppSettings(true)
                    }
                    dialog.setShowDialog(true)
                }
            }
        }
    )

    var launch = false
    permissions.forEach { permission ->
        val isGranted = activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

        launch = !isGranted
        if (launch) { warn("Permission is not granted: $permission.") }
    }

    if (launch) {
        LaunchedEffect(Unit) {
            tryLog(DebugMessageType.Error) {
                launcher.launch(permissions)
            }
        }
    }

    if (dialog.getShowDialog()) {
        val launchAppSettings = dialog.getLaunchAppSettings()
        dialog.Compose {
            if (launchAppSettings) {
                tryLog(DebugMessageType.Error) {
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null)
                    ).also {
                        activity.startActivity(it)
                    }
                    activity.finish()

                    dialog.setLaunchAppSettings(false)
                }
            } else {
                launcher.launch(permissions)
            }
            dialog.setShowDialog(false)
        }
    }
}