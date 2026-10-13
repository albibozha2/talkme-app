import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gis;

Widget googleWebButton(String locale) => gis.renderButton(
  configuration: gis.GSIButtonConfiguration(
    type: gis.GSIButtonType.standard,
    theme: gis.GSIButtonTheme.outline,
    size: gis.GSIButtonSize.large,
    text: gis.GSIButtonText.continueWith,
    shape: gis.GSIButtonShape.pill,
    minimumWidth: 300,
    locale: locale,
  ),
);
