from whisper_flow.ui.pages.crud import CrudPageRefs, build_crud_page
from whisper_flow.ui.pages.history import HistoryPageRefs, build_history_page
from whisper_flow.ui.pages.home import HomePageRefs, build_home_page
from whisper_flow.ui.pages.permissions import (
    PermissionRowRefs,
    PermissionsPageRefs,
    build_permission_wizard,
    build_permissions_page,
)
from whisper_flow.ui.pages.settings import SettingsPageRefs, build_settings_page

__all__ = [
    "CrudPageRefs",
    "HistoryPageRefs",
    "HomePageRefs",
    "PermissionRowRefs",
    "PermissionsPageRefs",
    "SettingsPageRefs",
    "build_crud_page",
    "build_history_page",
    "build_home_page",
    "build_permission_wizard",
    "build_permissions_page",
    "build_settings_page",
]
