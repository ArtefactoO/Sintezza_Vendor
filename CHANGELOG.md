# Changelog

## 2.2.0

- The settings header shows the addon version.
- The merchant window shows the version beside the title.
- Made the purchase limit field more compact and added a gold coin icon.

- Reduced repeated bag scans and stabilized the exclusions list while item information loads.
- Shortened the purchase-limit field and moved its explanation to a help tooltip.

- Made exclusions compact with item icons and quality colors, and added a shortcut in the merchant window.
- Moved all selling options into one list and clarified the binding filter.
- Automatically exclude recognized profession tools in bags for each character, announce additions in chat, and preserve manual removals.

- Left-clicking the minimap icon opens or closes the window.

- Connected window scale, opacity, and layer to the shared Theme settings. The WoW AddOns settings launcher uses the shared Theme helper.

- Updated the project logo and in-game addon icon.

- Use Sintezza Disenchant estimates and restrictions whenever their API functions are available.

### По-русски

- В шапке настроек отображается версия аддона.
- В окне торговца версия отображается рядом с названием.
- Поле лимита покупки стало компактнее, рядом появился значок золота.

- Сокращено повторное сканирование сумок; список исключений больше не пересортировывается во время загрузки данных предметов.
- Поле лимита покупки стало короче, пояснение перенесено в подсказку.

- Список исключений стал компактнее: добавлены иконки и цвета качества предметов, в окне торговца появился быстрый переход.
- Все настройки продажи перенесены в общий список, действие фильтра привязки пояснено.
- Распознанные инструменты профессий в сумках автоматически добавляются в исключения персонажа с сообщением в чат; ручное снятие исключения сохраняется.

- ЛКМ по значку у миникарты открывает или закрывает окно.

- Масштаб, непрозрачность и слой окон подключены к общим настройкам Theme. Страница в меню модификаций использует общую реализацию Theme.

- Обновлены логотип проекта и игровая иконка аддона.

- Разбор добычи использует оценки и ограничения Sintezza Disenchant, когда доступны соответствующие функции.

## 2.1.18

- Mastercraft recommendations in Loot Review follow the selected Sintezza language.

### По-русски

- Советы Mastercraft в разборе добычи выводятся на выбранном языке Sintezza.

## 2.1.17

- Integrated Loot Review as a merchant tab and removed the Bags tab, bulk sales by quality, and catalogue drop-down filters.
- Use Sintezza Disenchant's restrictions when comparing loot values.

## 2.1.16

- Added themed hints for quick-sale confirmations and the sale binding filter.

### По-русски

- Добавлены подсказки темы для подтверждения быстрой продажи и фильтра по привязке.

## 2.1.15

- Added a **Last sale** shortcut to the catalogue footer. It shows the latest sold stack and its price, and advances after a confirmed buyback.

## 2.1.14

- Corrected auction and disenchant estimates from Mastercraft when its auction-fee option is disabled. Loot Review now accounts for the 5% fee once.
- Ignore incomplete or malformed Mastercraft price data and use a fallback estimate when one is available.
- Added the MIT license and updated the installation, usage, and integration documentation.
