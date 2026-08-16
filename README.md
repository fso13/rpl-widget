# Календарь для macOS

Нативный виджет WidgetKit для рабочего стола и Центра уведомлений. События читаются из стандартного приложения «Календарь».

Система показывает виджеты только у обычного приложения из **/Applications**. Поэтому контейнер нужно туда скопировать и один раз запустить. Иконка в Dock после запуска скрывается сама.

## Установка

```bash
cd "/Users/rudenkodmitry/Documents/Личное/виджет календарь для мак"
xcodebuild -scheme CalendarHost -configuration Release -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY="-" AD_HOC_CODE_SIGNING_ALLOWED=YES
rm -rf "/Applications/CalendarHost.app"
cp -R DerivedData/Build/Products/Release/CalendarHost.app /Applications/
xattr -cr /Applications/CalendarHost.app
open /Applications/CalendarHost.app
```

Затем:

1. Если появится окно — нажмите **Разрешить доступ**.
2. Правый клик по рабочему столу → **Изменить виджеты** (или клик по дате в строке меню).
3. Найдите **Календарь** (не системный виджет из приложения Календарь Apple).

Долгое нажатие на виджет → правки: неделя с понедельника, номера недель, праздники, **матчи РПЛ** и **Кубок России**. Матчи дня показываются логотипами команд (календарь [РПЛ](https://matchtv.ru/football/rpl/calendar) и [Кубка](https://matchtv.ru/football/russian-cup/calendar) на Матч ТВ).
