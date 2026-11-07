import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// Reticule: a scope reticle face for the Forerunner 165 (390 x 390, AMOLED).
// Every position is an offset from the screen centre.
class ReticuleView extends WatchUi.WatchFace {

    // Palette
    const AMARANTH = 0xE8284F;
    const WHITE = 0xFFFFFF;
    const SOFT = 0xC4C4C4;
    const ICON = 0x9A9A9A;
    const LABEL = 0x7A7A7A;
    const DIM = 0x333333;
    const BLACK = 0x000000;
    const AOD_GREY = 0xB0B0B0;
    const POST = 0x505050;

    // Outer mil ring
    const RING_OUT = 192;
    const RING_MINOR = 185;
    const RING_MAJOR = 178;

    // Hours and minutes
    const DIGIT_W = 48;
    const DIGIT_H = 88;
    const DIGIT_S = 11;
    const DIGIT_GAP = 8;
    const CENTER_GAP = 18;

    // Seconds, read under the target like a range scale
    const SEC_W = 12;
    const SEC_H = 26;
    const SEC_S = 3;
    const SEC_GAP = 4;

    // Rows, as vertical offsets from the centre
    const STATUS_Y = -142;
    const WEATHER_Y = -107;
    const DATE_Y = -73;
    const TIME_Y = -9;
    const ROW_1 = 62;
    const ROW_2 = 95;
    const ROW_3 = 127;
    const COLUMN_1 = 98;
    const COLUMN_2 = 91;

    // Icons
    const ICON_HEART = 0;
    const ICON_FEET = 1;
    const ICON_PIN = 2;
    const ICON_BOLT = 3;
    const ICON_FLAME = 4;
    const ICON_WATCH = 5;
    const ICON_SUN = 6;
    const ICON_BATTERY = 7;

    // Sky kinds
    const SKY_CLEAR = 0;
    const SKY_PARTLY = 1;
    const SKY_CLOUD = 2;
    const SKY_RAIN = 3;
    const SKY_SNOW = 4;
    const SKY_STORM = 5;
    const SKY_FOG = 6;
    const SKY_WIND = 7;

    // Seven segments, bit order: a b c d e f g
    hidden var _segments = [0x7E, 0x30, 0x6D, 0x79, 0x33, 0x5B, 0x5F, 0x70, 0x7F, 0x7B];

    hidden var _days = ["DIM", "LUN", "MAR", "MER", "JEU", "VEN", "SAM"];
    hidden var _months = ["JAN", "FÉV", "MAR", "AVR", "MAI", "JUIN", "JUIL", "AOÛT", "SEP", "OCT", "NOV", "DÉC"];

    // Weather.CONDITION_* (0 to 53) mapped to a sky kind
    hidden var _skyKinds = [
        0, 1, 2, 3, 4, 7, 5, 4, 6, 6,
        4, 3, 5, 3, 3, 3, 4, 4, 4, 4,
        2, 4, 1, 0, 3, 3, 3, 3, 5, 6,
        6, 3, 5, 6, 4, 6, 5, 6, 6, 6,
        0, 5, 5, 4, 4, 3, 4, 4, 4, 3,
        4, 4, 1, 2
    ];

    // Always-on drift. Each step moves both axes by at least the stroke width.
    hidden var _driftX = [-8, 0, 8, -4, 4];
    hidden var _driftY = [-4, 8, 0, 4, -8];

    hidden var _lowPower = false;
    hidden var _burnIn = false;

    // Slow data, refreshed once a minute
    hidden var _cacheMinute = -1;
    hidden var _weather = null;
    hidden var _bodyBattery = null;
    hidden var _sunTime = null;
    hidden var _sunRising = false;
    hidden var _night = false;
    hidden var _savedDegrees = null;

    hidden var _fontValue;
    hidden var _fontUnit;
    hidden var _fontTemp;
    hidden var _fontDate;

    function initialize() {
        WatchFace.initialize();
        var settings = System.getDeviceSettings();
        _burnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;

        var bold = ["RobotoCondensedBold", "RobotoBold", "RobotoRegular"];
        var regular = ["RobotoCondensedRegular", "RobotoRegular"];
        _fontValue = loadFont(bold, 25, Graphics.FONT_TINY);
        _fontUnit = loadFont(regular, 18, Graphics.FONT_XTINY);
        _fontTemp = loadFont(bold, 31, Graphics.FONT_SMALL);
        _fontDate = loadFont(bold, 22, Graphics.FONT_XTINY);
    }

    // Scalable Roboto when the watch has it, system font otherwise.
    hidden function loadFont(faces, size, fallback) {
        if (Graphics has :getVectorFont) {
            try {
                var font = Graphics.getVectorFont({:face => faces, :size => size});
                if (font != null) {
                    return font;
                }
            } catch (e) {
            }
        }
        return fallback;
    }

    function onEnterSleep() {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        dc.setColor(WHITE, BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var clock = System.getClockTime();

        if (_lowPower && _burnIn) {
            drawAlwaysOn(dc, cx, cy, clock);
            return;
        }

        if (clock.min != _cacheMinute) {
            refreshSlowData(clock);
            _cacheMinute = clock.min;
        }

        var info = ActivityMonitor.getInfo();
        var settings = System.getDeviceSettings();
        var steps = (info.steps != null) ? info.steps : 0;
        var goal = (info.stepGoal != null && info.stepGoal > 0) ? info.stepGoal : 10000;

        drawRing(dc, cx, cy, steps, goal);
        drawReticle(dc, cx, cy, cy + TIME_Y);
        drawStatus(dc, cx, cy + STATUS_Y, settings);
        drawWeather(dc, cx, cy + WEATHER_Y, settings);
        drawDate(dc, cx, cy + DATE_Y, settings);
        drawTime(dc, cx, cy + TIME_Y, clock, DIGIT_S, WHITE, !_lowPower);
        drawTarget(dc, cx, cy + TIME_Y);
        drawData(dc, cx, cy, info, steps, settings);
    }

    // ---------------------------------------------------------------- data

    hidden function refreshSlowData(clock) {
        _bodyBattery = getBodyBattery();
        _weather = null;
        if (Toybox has :Weather) {
            _weather = Weather.getCurrentConditions();
        }
        refreshSun(clock);
    }

    // Next sunrise or sunset, from the weather location or the last GPS fix.
    hidden function refreshSun(clock) {
        _sunTime = null;
        _night = (clock.hour < 7) || (clock.hour >= 20);

        var location = null;
        if (_weather != null) {
            location = validLocation(_weather.observationLocationPosition);
        }
        if (location == null) {
            var activity = Activity.getActivityInfo();
            if (activity != null) {
                location = validLocation(activity.currentLocation);
            }
        }
        if (location != null) {
            // Saved only when it moves by about 5 km, to spare the flash memory.
            var degrees = location.toDegrees();
            var saved = _savedDegrees;
            if (saved == null || farApart(saved[0], degrees[0]) || farApart(saved[1], degrees[1])) {
                Application.Storage.setValue("location", degrees);
                _savedDegrees = degrees;
            }
        } else {
            var saved = Application.Storage.getValue("location");
            if (saved instanceof Array && saved.size() == 2) {
                location = new Position.Location({:latitude => saved[0], :longitude => saved[1], :format => :degrees});
            }
        }
        if (location == null || !(Toybox has :Weather) || !(Weather has :getSunset)) {
            return;
        }

        var now = Time.now();
        var sunrise = Weather.getSunrise(location, now);
        var sunset = Weather.getSunset(location, now);
        if (sunrise == null || sunset == null) {
            return;
        }
        if (now.value() < sunrise.value()) {
            _sunTime = sunrise;
            _sunRising = true;
            _night = true;
        } else if (now.value() < sunset.value()) {
            _sunTime = sunset;
            _sunRising = false;
            _night = false;
        } else {
            _sunTime = Weather.getSunrise(location, now.add(new Time.Duration(86400)));
            _sunRising = true;
            _night = true;
        }
    }

    hidden function farApart(a, b) {
        var d = a - b;
        return d > 0.05 || d < -0.05;
    }

    // Watches report 0,0 or 180,180 when they have no real fix.
    hidden function validLocation(location) {
        if (location == null) {
            return null;
        }
        var degrees = location.toDegrees();
        var lat = degrees[0];
        var lon = degrees[1];
        if (lat > 90 || lat < -90 || (lat < 0.01 && lat > -0.01 && lon < 0.01 && lon > -0.01)) {
            return null;
        }
        return location;
    }

    hidden function getHeartRate() {
        var activity = Activity.getActivityInfo();
        if (activity != null && activity.currentHeartRate != null) {
            return activity.currentHeartRate;
        }
        var history = ActivityMonitor.getHeartRateHistory(1, true);
        if (history != null) {
            var sample = history.next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    // Asks for exactly one sample: short Duration periods can crash on this API.
    hidden function getBodyBattery() {
        if ((Toybox has :SensorHistory) && (Toybox.SensorHistory has :getBodyBatteryHistory)) {
            var history = Toybox.SensorHistory.getBodyBatteryHistory({:period => 1});
            if (history != null) {
                var sample = history.next();
                if (sample != null && sample.data != null) {
                    return sample.data.toNumber();
                }
            }
        }
        return null;
    }

    // ---------------------------------------------------------------- format

    hidden function roundNumber(value) {
        return (value < 0) ? (value - 0.5).toNumber() : (value + 0.5).toNumber();
    }

    hidden function formatTemp(celsius, statute) {
        var value = statute ? (celsius * 9.0 / 5.0 + 32.0) : celsius.toFloat();
        return roundNumber(value).toString();
    }

    // Centimetres to "4,8" in km or miles, with a French decimal comma.
    hidden function formatDistance(centimetres, metric) {
        if (centimetres == null) {
            return "0,0";
        }
        var tenths = metric ? (centimetres / 10000) : (centimetres / 16093.44).toNumber();
        return (tenths / 10).toString() + "," + (tenths % 10).toString();
    }

    hidden function formatHour(hour) {
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour;
    }

    // ---------------------------------------------------------------- layout

    // Outer mil scale: 60 ticks, lit clockwise with the daily step goal.
    hidden function drawRing(dc, cx, cy, steps, goal) {
        var lit = (steps * 60) / goal;
        if (lit > 60) {
            lit = 60;
        }
        for (var i = 0; i < 60; i++) {
            var major = (i % 5) == 0;
            var angle = i * Math.PI / 30.0;
            var sinA = Math.sin(angle);
            var cosA = Math.cos(angle);
            var inner = major ? RING_MAJOR : RING_MINOR;
            dc.setPenWidth(major ? 3 : 2);
            dc.setColor(i < lit ? AMARANTH : DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(
                cx + (sinA * inner).toNumber(), cy - (cosA * inner).toNumber(),
                cx + (sinA * RING_OUT).toNumber(), cy - (cosA * RING_OUT).toNumber()
            );
        }
    }

    // Phone link, notifications, do not disturb.
    hidden function drawStatus(dc, cx, y, settings) {
        var count = (settings.notificationCount != null) ? settings.notificationCount : 0;
        var countText = count.toString();
        var countW = (count > 0) ? 5 + dc.getTextWidthInPixels(countText, _fontValue) : 0;
        var dnd = (settings has :doNotDisturb) && settings.doNotDisturb;
        var total = 10 + 18 + 20 + countW + (dnd ? 18 + 14 : 0);
        var x = cx - (total / 2);

        drawBluetooth(dc, x + 5, y, settings.phoneConnected ? SOFT : DIM);
        x += 10 + 18;
        drawEnvelope(dc, x, y, (count > 0) ? AMARANTH : DIM);
        x += 20;
        if (count > 0) {
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + 5, y, _fontValue, countText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += countW;
        }
        if (dnd) {
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            drawMoon(dc, x + 18 + 7, y, 7);
        }
    }

    hidden function drawWeather(dc, cx, y, settings) {
        var w = _weather;
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        if (w == null || w.temperature == null) {
            dc.setColor(LABEL, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, _fontUnit, "MÉTÉO --", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var statute = settings.temperatureUnits == System.UNIT_STATUTE;
        var kind = SKY_CLOUD;
        if (w.condition != null && w.condition >= 0 && w.condition < _skyKinds.size()) {
            kind = _skyKinds[w.condition];
        }
        var temp = formatTemp(w.temperature, statute) + "°";
        var range = "";
        if (w.lowTemperature != null && w.highTemperature != null) {
            range = formatTemp(w.lowTemperature, statute) + "/" + formatTemp(w.highTemperature, statute) + "°";
        }
        var rain = (w.precipitationChance != null) ? w.precipitationChance.toString() + "%" : "";

        var gap = 8;
        var tempW = dc.getTextWidthInPixels(temp, _fontTemp);
        var rangeW = (range.length() > 0) ? gap + dc.getTextWidthInPixels(range, _fontUnit) : 0;
        var rainW = (rain.length() > 0) ? gap + 15 + dc.getTextWidthInPixels(rain, _fontUnit) : 0;
        var x = cx - ((30 + gap + tempW + rangeW + rainW) / 2);

        drawSky(dc, x + 15, y, kind);
        x += 30 + gap;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _fontTemp, temp, left);
        x += tempW;
        if (rangeW > 0) {
            dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + gap, y + 2, _fontUnit, range, left);
            x += rangeW;
        }
        if (rainW > 0) {
            dc.setColor(ICON, Graphics.COLOR_TRANSPARENT);
            drawDrop(dc, x + gap + 5, y);
            dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + gap + 15, y + 2, _fontUnit, rain, left);
        }
    }

    // Date, then the next sunrise or sunset when a location is known.
    hidden function drawDate(dc, cx, y, settings) {
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = _days[now.day_of_week - 1] + " " + now.day.format("%02d") + " " + _months[now.month - 1];
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        var sunText = null;
        if (_sunTime != null) {
            var t = Gregorian.info(_sunTime, Time.FORMAT_SHORT);
            sunText = formatHour(t.hour).format("%02d") + ":" + t.min.format("%02d");
        }
        var dateW = dc.getTextWidthInPixels(text, _fontDate);
        var sunW = (sunText != null) ? 16 + 18 + 5 + dc.getTextWidthInPixels(sunText, _fontDate) : 0;
        var x = cx - ((dateW + sunW) / 2);

        dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _fontDate, text, left);
        if (sunText != null) {
            drawIcon(dc, ICON_SUN, x + dateW + 16 + 9, y, _sunRising ? 1 : 0);
            dc.setColor(ICON, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + dateW + 16 + 18 + 5, y, _fontDate, sunText, left);
        }
    }

    hidden function drawTime(dc, cx, cy, clock, stroke, color, seconds) {
        var hour = formatHour(clock.hour);
        var top = cy - (DIGIT_H / 2);
        var left = cx - CENTER_GAP - DIGIT_GAP - (DIGIT_W * 2);
        var right = cx + CENTER_GAP;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawDigit(dc, hour / 10, left, top, DIGIT_W, DIGIT_H, stroke);
        drawDigit(dc, hour % 10, left + DIGIT_W + DIGIT_GAP, top, DIGIT_W, DIGIT_H, stroke);
        drawDigit(dc, clock.min / 10, right, top, DIGIT_W, DIGIT_H, stroke);
        drawDigit(dc, clock.min % 10, right + DIGIT_W + DIGIT_GAP, top, DIGIT_W, DIGIT_H, stroke);

        if (seconds) {
            var sx = cx - ((SEC_W * 2 + SEC_GAP) / 2);
            var sy = top + DIGIT_H - SEC_H;
            dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
            drawDigit(dc, clock.sec / 10, sx, sy, SEC_W, SEC_H, SEC_S);
            drawDigit(dc, clock.sec % 10, sx + SEC_W + SEC_GAP, sy, SEC_W, SEC_H, SEC_S);
        }
    }

    hidden function drawDigit(dc, value, x, y, w, h, s) {
        var mask = _segments[value];
        if (value == 1) {
            // A right-hand 1 leaves a hole at 10, 11, 21: centre it in its cell.
            x -= (w - s) / 2;
        }
        var mid = y + (h / 2) - (s / 2);
        var half = (h / 2) + (s / 2);
        if ((mask & 0x40) != 0) { dc.fillRectangle(x, y, w, s); }
        if ((mask & 0x20) != 0) { dc.fillRectangle(x + w - s, y, s, half); }
        if ((mask & 0x10) != 0) { dc.fillRectangle(x + w - s, mid, s, half); }
        if ((mask & 0x08) != 0) { dc.fillRectangle(x, y + h - s, w, s); }
        if ((mask & 0x04) != 0) { dc.fillRectangle(x, mid, s, half); }
        if ((mask & 0x02) != 0) { dc.fillRectangle(x, y, s, half); }
        if ((mask & 0x01) != 0) { dc.fillRectangle(x, mid, w, s); }
    }

    // Duplex reticle: thick posts on the ring, thin stadia up to the digits.
    hidden function drawReticle(dc, cx, cy, ty) {
        var edge = CENTER_GAP + DIGIT_GAP + (DIGIT_W * 2) + 10;
        dc.setColor(POST, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 172, ty - 2, 20, 4);
        dc.fillRectangle(cx + 152, ty - 2, 20, 4);
        dc.fillRectangle(cx - 152, ty - 1, 152 - edge, 2);
        dc.fillRectangle(cx + edge, ty - 1, 152 - edge, 2);
        dc.fillCircle(cx - edge - 10, ty, 2);
        dc.fillCircle(cx + edge + 10, ty, 2);
        dc.fillRectangle(cx - 2, cy - 176, 4, 16);
        dc.fillRectangle(cx - 2, cy + 160, 4, 16);
    }

    hidden function drawTarget(dc, cx, cy) {
        dc.setColor(AMARANTH, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, 11);
        dc.fillCircle(cx, cy, 4);
    }

    hidden function drawData(dc, cx, cy, info, steps, settings) {
        var metric = settings.distanceUnits != System.UNIT_STATUTE;

        // Row 1: heart rate, steps, distance
        var hr = getHeartRate();
        drawItem(dc, cx - COLUMN_1, cy + ROW_1, 0, ICON_HEART, 0, (hr != null) ? hr.toString() : "--", "", WHITE, _fontValue);
        drawItem(dc, cx, cy + ROW_1, 0, ICON_FEET, 0, steps.toString(), "", WHITE, _fontValue);
        drawItem(dc, cx + COLUMN_1, cy + ROW_1, 0, ICON_PIN, 0, formatDistance(info.distance, metric), metric ? "km" : "mi", WHITE, _fontValue);

        // Row 2: Body Battery, calories, weekly intensity minutes
        var body = (_bodyBattery != null) ? _bodyBattery.toString() : "--";
        drawItem(dc, cx - COLUMN_2, cy + ROW_2, 0, ICON_BOLT, 0, body, "", SOFT, _fontDate);
        var kcal = (info.calories != null) ? info.calories.toString() : "--";
        drawItem(dc, cx, cy + ROW_2, 0, ICON_FLAME, 0, kcal, "", SOFT, _fontDate);
        var minutes = 0;
        if (info.activeMinutesWeek != null && info.activeMinutesWeek.total != null) {
            minutes = info.activeMinutesWeek.total;
        }
        var weekGoal = (info.activeMinutesWeekGoal != null && info.activeMinutesWeekGoal > 0)
            ? info.activeMinutesWeekGoal : 150;
        drawItem(dc, cx + COLUMN_2, cy + ROW_2, 0, ICON_WATCH, 0, minutes.toString(), "min",
            (minutes >= weekGoal) ? AMARANTH : SOFT, _fontDate);

        // Row 3: battery level and estimated days left
        var stats = System.getSystemStats();
        var battery = roundNumber(stats.battery);
        var autonomy = "";
        if (stats has :batteryInDays) {
            var days = stats.batteryInDays;
            autonomy = (days >= 1.0) ? days.toNumber().toString() + " j" : (days * 24).toNumber().toString() + " h";
        }
        drawItem(dc, cx, cy + ROW_3, 0, ICON_BATTERY, battery, battery.toString() + "%", autonomy,
            (battery <= 20) ? AMARANTH : SOFT, _fontDate);
    }

    // Icon, value and optional unit. align: -1 right edge at x, 0 centred, 1 left edge at x.
    hidden function drawItem(dc, x, y, align, icon, arg, value, unit, color, font) {
        var iconW = (icon == ICON_BATTERY) ? 26 : 18;
        var gap = 6;
        var valueW = dc.getTextWidthInPixels(value, font);
        var unitW = (unit.length() > 0) ? 4 + dc.getTextWidthInPixels(unit, _fontUnit) : 0;
        var total = iconW + gap + valueW + unitW;
        var start = x - (total / 2);
        if (align < 0) {
            start = x - total;
        } else if (align > 0) {
            start = x;
        }
        var leftV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        drawIcon(dc, icon, start + (iconW / 2), y, arg);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(start + iconW + gap, y, font, value, leftV);
        if (unitW > 0) {
            dc.setColor(LABEL, Graphics.COLOR_TRANSPARENT);
            dc.drawText(start + iconW + gap + valueW + 4, y + 2, _fontUnit, unit, leftV);
        }
    }

    hidden function drawAlwaysOn(dc, cx, cy, clock) {
        var index = clock.min % 5;
        var x = cx + _driftX[index];
        var y = cy + _driftY[index];
        drawTime(dc, x, y, clock, 4, AOD_GREY, false);
        dc.setColor(AMARANTH, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 3);
    }

    // ---------------------------------------------------------------- icons

    hidden function drawIcon(dc, icon, x, y, arg) {
        var color = ICON;
        if (icon == ICON_BATTERY && arg <= 20) {
            color = AMARANTH;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        if (icon == ICON_HEART) {
            dc.fillCircle(x - 4, y - 2, 4);
            dc.fillCircle(x + 4, y - 2, 4);
            dc.fillPolygon([[x - 8, y - 1], [x + 8, y - 1], [x, y + 7]]);
        } else if (icon == ICON_FEET) {
            dc.fillEllipse(x - 4, y - 1, 3, 5);
            dc.fillEllipse(x - 4, y + 7, 3, 2);
            dc.fillEllipse(x + 4, y - 5, 3, 5);
            dc.fillEllipse(x + 4, y + 3, 3, 2);
        } else if (icon == ICON_PIN) {
            dc.fillCircle(x, y - 3, 6);
            dc.fillPolygon([[x - 5, y], [x + 5, y], [x, y + 8]]);
            dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y - 3, 2);
        } else if (icon == ICON_BOLT) {
            dc.fillPolygon([[x + 2, y - 8], [x - 5, y + 1], [x, y + 1], [x - 2, y + 8], [x + 5, y - 1], [x, y - 1]]);
        } else if (icon == ICON_FLAME) {
            // Two tongues and a hollow core, so it never reads as a rain drop.
            dc.fillCircle(x, y + 3, 6);
            dc.fillPolygon([[x - 6, y + 3], [x - 5, y - 4], [x - 2, y - 1], [x + 1, y - 9], [x + 6, y - 1], [x + 6, y + 3]]);
            dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y + 5, 3);
            dc.fillPolygon([[x - 3, y + 5], [x + 3, y + 5], [x + 1, y - 1]]);
        } else if (icon == ICON_WATCH) {
            dc.drawCircle(x, y + 1, 6);
            dc.fillRectangle(x - 2, y - 8, 4, 2);
            dc.drawLine(x, y + 1, x + 3, y - 2);
        } else if (icon == ICON_SUN) {
            dc.fillCircle(x, y + 4, 5);
            dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x - 6, y + 4, 13, 6);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x - 8, y + 5, 16, 2);
            if (arg == 1) {
                dc.fillPolygon([[x - 3, y - 4], [x + 3, y - 4], [x, y - 8]]);
            } else {
                dc.fillPolygon([[x - 3, y - 8], [x + 3, y - 8], [x, y - 4]]);
            }
        } else if (icon == ICON_BATTERY) {
            dc.fillRectangle(x - 12, y - 6, 22, 12);
            dc.fillRectangle(x + 10, y - 2, 2, 4);
            dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x - 10, y - 4, 18, 8);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            var level = (16 * arg) / 100;
            dc.fillRectangle(x - 9, y - 3, (level < 1) ? 1 : level, 6);
        }
    }

    hidden function drawBluetooth(dc, x, y, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x, y - 8, x, y + 8);
        dc.drawLine(x, y - 8, x + 4, y - 4);
        dc.drawLine(x + 4, y - 4, x - 4, y + 4);
        dc.drawLine(x, y + 8, x + 4, y + 4);
        dc.drawLine(x + 4, y + 4, x - 4, y - 4);
    }

    hidden function drawEnvelope(dc, x, y, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y - 7, 20, 14);
        dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 2, y - 5, 16, 10);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x + 2, y - 5, x + 10, y + 1);
        dc.drawLine(x + 10, y + 1, x + 18, y - 5);
    }

    hidden function drawDrop(dc, x, y) {
        dc.fillCircle(x, y + 2, 4);
        dc.fillPolygon([[x - 4, y + 1], [x + 4, y + 1], [x, y - 6]]);
    }

    // Uses the current colour.
    hidden function drawSun(dc, x, y, r) {
        dc.fillCircle(x, y, r);
        dc.setPenWidth(2);
        for (var i = 0; i < 8; i++) {
            var angle = i * Math.PI / 4.0;
            var sinA = Math.sin(angle);
            var cosA = Math.cos(angle);
            dc.drawLine(
                x + (sinA * (r + 3)).toNumber(), y - (cosA * (r + 3)).toNumber(),
                x + (sinA * (r + 6)).toNumber(), y - (cosA * (r + 6)).toNumber()
            );
        }
    }

    // Crescent: uses the current colour, then cuts with black.
    hidden function drawMoon(dc, x, y, r) {
        dc.fillCircle(x, y, r);
        dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + (r / 2) + 1, y - (r / 2), r - 1);
    }

    hidden function drawCloud(dc, x, y, grow, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 6, y + 2, 6 + grow);
        dc.fillCircle(x + 1, y - 3, 8 + grow);
        dc.fillCircle(x + 8, y + 3, 5 + grow);
        dc.fillRectangle(x - 6, y + 2, 14, 6 + grow);
    }

    hidden function drawSky(dc, x, y, kind) {
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (kind == SKY_CLEAR) {
            if (_night) {
                drawMoon(dc, x, y, 9);
            } else {
                drawSun(dc, x, y, 6);
            }
        } else if (kind == SKY_PARTLY) {
            if (_night) {
                drawMoon(dc, x - 5, y - 5, 7);
            } else {
                drawSun(dc, x - 5, y - 5, 4);
            }
            drawCloud(dc, x + 3, y + 3, 2, BLACK);
            drawCloud(dc, x + 3, y + 3, 0, WHITE);
        } else if (kind == SKY_FOG) {
            dc.fillRectangle(x - 10, y - 7, 20, 3);
            dc.fillRectangle(x - 7, y - 1, 16, 3);
            dc.fillRectangle(x - 10, y + 5, 20, 3);
        } else if (kind == SKY_WIND) {
            dc.fillRectangle(x - 10, y - 6, 16, 3);
            dc.fillRectangle(x - 6, y - 1, 18, 3);
            dc.fillRectangle(x - 10, y + 4, 12, 3);
        } else if (kind == SKY_CLOUD) {
            drawCloud(dc, x, y, 0, WHITE);
        } else {
            drawCloud(dc, x, y - 5, 0, WHITE);
            for (var i = 0; i < 3; i++) {
                var px = x - 6 + (i * 6);
                if (kind == SKY_RAIN) {
                    dc.drawLine(px + 1, y + 6, px - 1, y + 11);
                } else if (kind == SKY_SNOW) {
                    dc.fillCircle(px, y + 8 + ((i % 2) * 3), 2);
                }
            }
            if (kind == SKY_STORM) {
                dc.fillPolygon([[x + 1, y + 3], [x - 4, y + 10], [x, y + 10], [x - 2, y + 15], [x + 4, y + 7], [x, y + 7], [x + 2, y + 3]]);
            }
        }
    }
}
