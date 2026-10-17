# Account-level setting: metrics only. The account itself emits no log
# categories - data-plane logs live on the blob service below.
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.platform.id

  enabled_metric {
    category = "AllMetrics"
  }
}

# Blob data-plane logs attach to <account>/blobServices/default. A setting on
# the account alone collects no StorageRead/Write/Delete while looking configured.
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.platform.id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
