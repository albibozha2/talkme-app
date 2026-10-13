bool get tabVisible => true;
bool get canPopUp => false;
bool get canAskPopUp => false;
Future<bool> askPopUpPermission() async => false;
void setTabTitle(String title) {}
void popUp(String title, String body, void Function() onClick) {}
void onTabVisible(void Function() callback) {}
bool get showInstallHint => false;
String get popUpPermission => 'unsupported';
