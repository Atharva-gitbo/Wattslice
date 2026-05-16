/*
 * ESP32 — WattSlice Controller + R4 Miniature Bridge
 *
 * Existing functionality preserved exactly:
 *   LCD menu, buttons, potentiometer, ultrasonic, LEDs, NTP, state machine
 *
 * Added (R4 communication):
 *   WiFi AP  "ESP32_AP" / "12345678"  → R4 connects here
 *   WiFi STA "AtharvaHotspot"         → NTP (existing, unchanged)
 *   TCP server port 8080              → receives power JSON from R4
 *                                        sends mode/device commands to R4
 *
 * Added (Flutter app communication):
 *   TCP server port 8081              → Flutter app connects via AtharvaHotspot
 *                                        receives power JSON forwarded from R4
 *                                        sends device/mode commands to ESP32
 *
 * Appliance → R4 device mapping:
 *   apps[0] Mini Fan  → "fan"
 *   apps[1] Speaker   → "buzzer"
 *   apps[2] Light     → "led"
 *
 * Commands sent to R4 on key transitions:
 *   Eco Mode Now       → {"cmd":"mode","value":"eco"}
 *   Smart Delay        → {"cmd":"mode","value":"smart_delay"}
 *   Ignore / Reset     → {"cmd":"mode","value":"normal"}
 *   Appliance toggle   → {"cmd":"fan/buzzer/led","value":"on/off"}
 */

#include <WiFi.h>
#include <Wire.h>
#include "rgb_lcd.h"
#include <time.h>
#include <ArduinoJson.h>
#include "esp_wifi.h"

// ================= Configuration =================
const char* WIFI_SSID = "AtharvaHotspot";
const char* WIFI_PASSWORD = "hellothere69";
const long  GMT_OFFSET_SEC = 10 * 3600;
const int   DAYLIGHT_OFFSET_SEC = 0;
const char* NTP_SERVER = "pool.ntp.org";

// ── R4 bridge ────────────────────────────────────────────────────
const char* AP_SSID = "ESP32_AP";
const char* AP_PASS = "12345678";
const int   TCP_PORT = 8080;
WiFiServer  r4Server(TCP_PORT);
WiFiClient  r4Client;

// ── Flutter app bridge ───────────────────────────────────────────
const int   FLUTTER_TCP_PORT = 8081;
WiFiServer  flutterServer(FLUTTER_TCP_PORT);
WiFiClient  flutterClient;

// ── Non-blocking receive buffers ─────────────────────────────────
String r4RxBuffer      = "";
String flutterRxBuffer = "";

// Smart delay scheduled resume time ("HH:MM" or "Pause 2h")
String       smartDelayUntil     = "";
unsigned long smartDelayPauseStart = 0;
const unsigned long PAUSE_DEMO_MS = 30000; // 30 s demo (represents 2 h)

#define LED_R 13
#define LED_Y 12
#define LED_G 14
#define ULTRA_SIG 25
#define BTN_1_PIN 27
#define BTN_2_PIN 35
#define POT_PIN   34

rgb_lcd lcd;

enum SystemState { NORMAL, PEAK_ALERT, ECO_MODE };
SystemState currentState = NORMAL;

enum MenuState {
  HOME_PAGE,
  APPLIANCE_LIST,
  APPLIANCE_ACTION_SELECT,    // choose Smart Delay / Eco / Off for active device
  APPLIANCE_SCHEDULE_SELECT,  // pick resume time for per-device smart delay
  APPLIANCE_TOGGLE_CONFIRM,   // confirm turning an OFF device back ON
  ALERT_INTRO,
  ALERT_PROMPT,
  CANCEL_PROMPT,
  MODE_SELECT,
  MODE_CANCEL_PROMPT,
  GLOBAL_SCHEDULE
};
MenuState currentMenuState = HOME_PAGE;

// ============================================================
// Grove LCD RGB Backlight compatibility layer (v3.0 / v4.0 / v5.0)
// ============================================================
static uint8_t LCD_RGB_ADDR = 0x62;

bool i2cProbe(uint8_t addr) {
  Wire.beginTransmission(addr);
  return Wire.endTransmission() == 0;
}

void v4_writeReg(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(LCD_RGB_ADDR);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission();
}

void setupRGB_v4() {
  if (i2cProbe(0x30))      LCD_RGB_ADDR = 0x30;
  else if (i2cProbe(0x62)) LCD_RGB_ADDR = 0x62;
  v4_writeReg(0x00, 0x00);
  v4_writeReg(0x01, 0x00);
  v4_writeReg(0x08, 0xAA);
}

void setRGB_v4(uint8_t r, uint8_t g, uint8_t b) {
  v4_writeReg(0x00, 0x00);
  delayMicroseconds(600);
  v4_writeReg(0x01, 0x00);
  v4_writeReg(0x08, 0xAA);
  v4_writeReg(0x04, r);
  v4_writeReg(0x03, g);
  v4_writeReg(0x02, b);
}

struct Appliance { String name; float power; int state; int scheduleIndex; };
Appliance apps[3] = {
  {"Mini Fan", 12.5, 1, -1},
  {"Speaker",   5.0, 1, -1},
  {"Light",     8.2, 1, -1}
};

// R4 device name matching apps[] order
const char* R4_DEVICE[] = { "fan", "buzzer", "led" };

const int NUM_TIMES = 5;
String scheduleTimes[NUM_TIMES] = {"22:00", "23:00", "00:00", "06:00", "Pause 2h"};

const float PEAK_RATE_PER_KWH = 0.45;
const int   PEAK_END_HOUR     = 21;

const int SIM_START_HOUR   = 17;
const int SIM_START_MINUTE = 48;
unsigned long simBootMillis = 0;

int modeIndex = 0;
int scrollIndex = 0;
int timeScrollIndex = 0;
int actionIndex = 0; // 0=Smart Delay  1=Eco Mode  2=Off
int lastStablePotRaw = -1;

int peakApplianceIndex = 0;

float ecoDisplayPower[3] = {0, 0, 0};
unsigned long lastEcoFlicker = 0;
const unsigned long ECO_FLICKER_INTERVAL = 2500;

int lastBtn1State = HIGH;
int lastBtn2State = LOW;
unsigned long lastBtn1Press = 0;
unsigned long lastBtn2Press = 0;
unsigned long lastLcdUpdate = 0;
unsigned long lastStateChange = 0;
unsigned long lastInteractionTime = 0;

unsigned long btn2PressedTime = 0;
bool btn2IsHolding = false;
const unsigned long HOLD_DETECT_MS  = 2000;
const unsigned long RESET_HOLD_TIME = 5000;

bool homeShowAltScreen = false;
unsigned long lastHomeToggle = 0;

unsigned long alertIntroStart = 0;
const unsigned long ALERT_INTRO_DURATION = 2500;

bool alertShowSwipe = true;
unsigned long lastAlertToggle = 0;
const unsigned long ALERT_PHASE_DURATION = 5000;

bool wifiReady = false;

// ================= R4 Communication =================

void sendCommandToR4(const String& cmd, const String& val) {
  if (!r4Client || !r4Client.connected()) {
    Serial.printf("[ESP→R4] DROPPED (R4 not connected): cmd=%s value=%s\n", cmd.c_str(), val.c_str());
    return;
  }
  StaticJsonDocument<64> doc;
  doc["cmd"]   = cmd;
  doc["value"] = val;
  String out;
  serializeJson(doc, out);
  out += '\n';
  r4Client.print(out);
  Serial.printf("[ESP→R4] SENT: %s", out.c_str());
}

// After any mode change, resync each device's on/off state so R4 matches ESP32
void syncDeviceStatesToR4() {
  for (int i = 0; i < 3; i++) {
    bool shouldBeOn = (apps[i].state == 1 || apps[i].state == 2);
    sendCommandToR4(R4_DEVICE[i], shouldBeOn ? "on" : "off");
  }
}

// ── NEW: send a full status snapshot to Flutter ──────────────────
// Called when Flutter connects so the app starts with correct state.
void sendStatusToFlutter() {
  if (!flutterClient || !flutterClient.connected()) return;
  StaticJsonDocument<256> doc;
  const char* modeStr = (currentState == ECO_MODE) ? "eco" : "normal";
  doc["mode"] = modeStr;
  JsonObject fan = doc.createNestedObject("fan");
  fan["state"] = apps[0].state;
  fan["p"]     = apps[0].power * 1000; // W → mW to match R4 format
  JsonObject buzzer = doc.createNestedObject("buzzer");
  buzzer["state"] = apps[1].state;
  buzzer["p"]     = apps[1].power * 1000;
  JsonObject led = doc.createNestedObject("led");
  led["state"] = apps[2].state;
  led["p"]     = apps[2].power * 1000;
  String out;
  serializeJson(doc, out);
  out += '\n';
  flutterClient.print(out);
}

// ── NEW: handle command received from Flutter app ────────────────
void onFlutterCommand(const String& line) {
  StaticJsonDocument<128> doc;
  if (deserializeJson(doc, line) != DeserializationError::Ok) return;

  const char* cmd   = doc["cmd"];
  const char* value = doc["value"];
  if (!cmd || !value) return;

  Serial.printf("[Flutter] cmd=%s value=%s\n", cmd, value);

  // Mode commands
  if (strcmp(cmd, "mode") == 0) {
    if (strcmp(value, "eco") == 0) {
      for (int i = 0; i < 3; i++) if (apps[i].state == 1) apps[i].state = 2;
      sendCommandToR4("mode", "eco");
      switchToState(ECO_MODE);
    } else if (strcmp(value, "smart_delay") == 0) {
      sendCommandToR4("mode", "smart_delay");
      switchToState(ECO_MODE);
    } else if (strcmp(value, "normal") == 0) {
      for (int i = 0; i < 3; i++) {
        if (apps[i].state == 2 || apps[i].state == 3) apps[i].state = 1;
      }
      smartDelayUntil = "";
      sendCommandToR4("mode", "normal");
      syncDeviceStatesToR4();
      switchToState(NORMAL);
    }
    currentMenuState = HOME_PAGE;
    updateLCDDisplay();
    return;
  }

  // Per-device commands (fan / buzzer / led)
  for (int i = 0; i < 3; i++) {
    if (strcmp(cmd, R4_DEVICE[i]) == 0) {
      bool turnOn = strcmp(value, "on") == 0;
      apps[i].state = turnOn ? 1 : 0;
      sendCommandToR4(R4_DEVICE[i], value);
      if (currentMenuState == APPLIANCE_LIST && scrollIndex == i) updateLCDDisplay();
      return;
    }
  }
}

// Updates apps[].power with real INA226 readings from R4 (mW → W)
void onR4Data(const String& raw) {
  StaticJsonDocument<320> doc;
  if (deserializeJson(doc, raw) != DeserializationError::Ok) return;

  // Log real miniature readings to Serial for verification
  Serial.print("[R4] mode="); Serial.print(doc["mode"] | "?");
  if (doc.containsKey("fan"))
    Serial.printf("  Fan=%.1fmW", doc["fan"]["p"].as<float>());
  if (doc.containsKey("led"))
    Serial.printf("  LED=%.1fmW", doc["led"]["p"].as<float>());
  if (doc.containsKey("buzzer"))
    Serial.printf("  Buz=%.1fmW", doc["buzzer"]["p"].as<float>());
  Serial.println();

  // ── NEW: forward R4 JSON verbatim to Flutter ─────────────────
  if (flutterClient && flutterClient.connected()) {
    flutterClient.println(raw);
  }

  // Refresh appliance list LCD
  if (currentMenuState == APPLIANCE_LIST) {
    updateLCDDisplay();
  }
}

// ================= Utilities =================

int findPeakAppliance() {
  int idx = 0;
  float maxP = -1.0;
  for (int i = 0; i < 3; i++) {
    if (apps[i].state == 1 && apps[i].power > maxP) {
      maxP = apps[i].power;
      idx = i;
    }
  }
  return idx;
}

void refreshEcoFlicker() {
  if (millis() - lastEcoFlicker < ECO_FLICKER_INTERVAL) return;
  lastEcoFlicker = millis();
  for (int i = 0; i < 3; i++) {
    if (apps[i].state == 2) {
      float lo, hi;
      if (apps[i].power >= 10.0) {
        lo = 5.5; hi = 10.0;
      } else {
        lo = apps[i].power * 0.3;
        hi = apps[i].power * 0.7;
      }
      ecoDisplayPower[i] = lo + (random(0, 1001) / 1000.0) * (hi - lo);
    }
  }
}

bool fetchRealTime(struct tm* out) {
  if (!wifiReady) return false;
  return getLocalTime(out, 50);
}

bool isAtDefaultHome() {
  return currentState == NORMAL && currentMenuState == HOME_PAGE;
}

void enterAlertPrompt() {
  currentMenuState = ALERT_PROMPT;
  alertShowSwipe = true;
  lastAlertToggle = millis();
}

int simHourNow() {
  unsigned long elapsedMin = (millis() - simBootMillis) / 60000UL;
  int totalMin = SIM_START_HOUR * 60 + SIM_START_MINUTE + (int)elapsedMin;
  return (totalMin / 60) % 24;
}

int simMinuteNow() {
  unsigned long elapsedMin = (millis() - simBootMillis) / 60000UL;
  int totalMin = SIM_START_HOUR * 60 + SIM_START_MINUTE + (int)elapsedMin;
  return totalMin % 60;
}

int getCurrentHour() {
  struct tm t;
  if (fetchRealTime(&t)) return t.tm_hour;
  return simHourNow();
}

int getCurrentMinute() {
  struct tm t;
  if (fetchRealTime(&t)) return t.tm_min;
  return simMinuteNow();
}

String getTimeString() {
  char buf[8];
  sprintf(buf, "%02d:%02d", getCurrentHour(), getCurrentMinute());
  return String(buf);
}

float computeTotalPowerOn() {
  float total = 0;
  for (int i = 0; i < 3; i++) {
    if (apps[i].state == 1) total += apps[i].power;
  }
  return total;
}

const char* scheduleRelativeDate(const String& timeStr) {
  if (timeStr.startsWith("Pause")) return "";
  int colonIdx = timeStr.indexOf(':');
  if (colonIdx < 0) return "";
  int hh = timeStr.substring(0, colonIdx).toInt();
  int mm = timeStr.substring(colonIdx + 1).toInt();
  int curH = getCurrentHour();
  int curM = getCurrentMinute();
  if (hh < curH || (hh == curH && mm <= curM)) return "Tmrw";
  return "Today";
}

float computePeakCostRemaining() {
  int h = getCurrentHour();
  int m = getCurrentMinute();
  float hoursLeft = (PEAK_END_HOUR - h) - (m / 60.0);
  if (hoursLeft <= 0) return 0;
  return computeTotalPowerOn() * hoursLeft * PEAK_RATE_PER_KWH / 1000.0;
}

void switchToState(SystemState newState) {
  currentState = newState;
  lastStateChange = millis();
  lastInteractionTime = millis();
  digitalWrite(LED_R, LOW); digitalWrite(LED_Y, LOW); digitalWrite(LED_G, LOW);
  if (newState == NORMAL)          { digitalWrite(LED_G, HIGH); setRGB_v4(60, 255, 0); }
  else if (newState == PEAK_ALERT) { digitalWrite(LED_R, HIGH); setRGB_v4(255, 0, 0); }
  else if (newState == ECO_MODE)   { digitalWrite(LED_Y, HIGH); setRGB_v4(255, 140, 0); }
}

void applyPageBackground() {
  bool isDecisionPage = (currentMenuState == MODE_SELECT
                       || currentMenuState == MODE_CANCEL_PROMPT
                       || currentMenuState == GLOBAL_SCHEDULE);
  bool isAlertPage    = (currentMenuState == ALERT_INTRO
                       || currentMenuState == ALERT_PROMPT
                       || currentMenuState == CANCEL_PROMPT);
  if (isDecisionPage)              setRGB_v4(255, 140, 0);
  else if (isAlertPage)            setRGB_v4(255, 0, 0);
  else if (currentState == NORMAL)     setRGB_v4(60, 255, 0);
  else if (currentState == PEAK_ALERT) setRGB_v4(255, 0, 0);
  else if (currentState == ECO_MODE)   setRGB_v4(255, 140, 0);
}

// ================= LCD Rendering =================
void updateLCDDisplay() {
  applyPageBackground();
  lcd.clear();

  if (btn2IsHolding && millis() - btn2PressedTime > HOLD_DETECT_MS) {
    lcd.setCursor(0, 0);
    lcd.print(isAtDefaultHome() ? "Hard Reset...   " : "Resetting...    ");
    int progress = ((millis() - btn2PressedTime) * 16) / RESET_HOLD_TIME;
    if (progress > 16) progress = 16;
    lcd.setCursor(0, 1);
    for (int i = 0; i < progress; i++) lcd.print(">");
    return;
  }

  switch (currentMenuState) {

    case HOME_PAGE: {
      String timeStr = getTimeString();
      lcd.setCursor(0, 0);
      lcd.print("WattSlice");
      int gap = 16 - 9 - timeStr.length();
      for (int i = 0; i < gap; i++) lcd.print(' ');
      lcd.print(timeStr);

      lcd.setCursor(0, 1);
      if (!homeShowAltScreen) {
        lcd.print("B1 -> List");
      } else {
        if (currentState == ECO_MODE) {
          int onC = 0, ecoC = 0;
          for (int i = 0; i < 3; i++) {
            if (apps[i].state == 1) onC++;
            else if (apps[i].state == 2 || apps[i].state == 3) ecoC++;
          }
          lcd.print("Run:"); lcd.print(onC);
          lcd.print(" Saving:"); lcd.print(ecoC);
        } else {
          int activeCount = 0;
          for (int i = 0; i < 3; i++) if (apps[i].state == 1) activeCount++;
          lcd.print("Running: "); lcd.print(activeCount);
        }
      }
      break;
    }

    case ALERT_INTRO:
      lcd.setCursor(0, 0); lcd.print("HIGH ENERGY");
      lcd.setCursor(0, 1); lcd.print("DETECTED!");
      break;

    case ALERT_PROMPT: {
      lcd.setCursor(0, 0);
      lcd.print(apps[peakApplianceIndex].name);
      lcd.print(" ");
      lcd.print(computeTotalPowerOn(), 1);
      lcd.print("W");

      lcd.setCursor(0, 1);
      if (alertShowSwipe) {
        lcd.print("Swipe to Confirm");
      } else {
        lcd.print("B1=Act  B2=Skip");
      }
      break;
    }

    case CANCEL_PROMPT:
      lcd.setCursor(0, 0); lcd.print("Ignore Alert?");
      lcd.setCursor(0, 1); lcd.print("YES(B1) NO(B2)");
      break;

    case MODE_SELECT:
      lcd.setCursor(0, 0); lcd.print(apps[peakApplianceIndex].name);
      lcd.setCursor(0, 1);
      if (modeIndex == 0) lcd.print("> Smart Delay");
      else                lcd.print("> Eco Mode Now");
      break;

    case MODE_CANCEL_PROMPT:
      lcd.setCursor(0, 0); lcd.print("Back to Alert?");
      lcd.setCursor(0, 1); lcd.print("YES(B1) NO(B2)");
      break;

    case GLOBAL_SCHEDULE: {
      lcd.setCursor(0, 0); lcd.print("Delay "); lcd.print(apps[peakApplianceIndex].name);
      lcd.setCursor(0, 1);
      lcd.print("> ");
      lcd.print(scheduleTimes[timeScrollIndex]);
      const char* relDate = scheduleRelativeDate(scheduleTimes[timeScrollIndex]);
      if (relDate[0] != '\0') {
        lcd.print(" ");
        lcd.print(relDate);
      }
      break;
    }

    case APPLIANCE_SCHEDULE_SELECT: {
      lcd.setCursor(0, 0); lcd.print("Delay "); lcd.print(apps[scrollIndex].name);
      lcd.setCursor(0, 1);
      lcd.print("> ");
      lcd.print(scheduleTimes[timeScrollIndex]);
      const char* relDate2 = scheduleRelativeDate(scheduleTimes[timeScrollIndex]);
      if (relDate2[0] != '\0') {
        lcd.print(" ");
        lcd.print(relDate2);
      }
      break;
    }

    case APPLIANCE_ACTION_SELECT: {
      String atag;
      if      (apps[scrollIndex].state == 2) atag = "[ECO]";
      else if (apps[scrollIndex].state == 3) atag = "[DEL]";
      else                                   atag = "[ON]";
      lcd.setCursor(0, 0);
      lcd.print(apps[scrollIndex].name);
      int apad = 16 - apps[scrollIndex].name.length() - atag.length();
      for (int i = 0; i < apad; i++) lcd.print(' ');
      lcd.print(atag);
      const char* actionLabels[] = { "Smart Delay", "Eco Mode", "Off" };
      lcd.setCursor(0, 1);
      String opt = String("> ") + actionLabels[actionIndex];
      while (opt.length() < 16) opt += ' ';
      lcd.print(opt);
      break;
    }

    case APPLIANCE_LIST: {
      String tag;
      if      (apps[scrollIndex].state == 0) tag = "[OFF]";
      else if (apps[scrollIndex].state == 2) tag = "[ECO]";
      else if (apps[scrollIndex].state == 3) tag = "[DEL]";
      else                                   tag = "[ON]";

      lcd.setCursor(0, 0);
      lcd.print(apps[scrollIndex].name);
      int pad = 16 - apps[scrollIndex].name.length() - tag.length();
      for (int i = 0; i < pad; i++) lcd.print(' ');
      lcd.print(tag);

      float dispP;
      if (apps[scrollIndex].state == 2)      dispP = ecoDisplayPower[scrollIndex];
      else if (apps[scrollIndex].state == 0) dispP = 0.0;
      else if (apps[scrollIndex].state == 3) dispP = 0.0;
      else                                   dispP = apps[scrollIndex].power;

      float kwhDay = dispP * 24.0 / 1000.0;
      lcd.setCursor(0, 1);
      lcd.print(dispP, 1); lcd.print("W ");
      lcd.print(kwhDay, 2); lcd.print("kWh/d");
      break;
    }

    case APPLIANCE_TOGGLE_CONFIRM:
      lcd.setCursor(0, 0); lcd.print(apps[scrollIndex].name);
      if      (apps[scrollIndex].state == 1) lcd.print(" [ON]");
      else if (apps[scrollIndex].state == 2) lcd.print(" [ECO]");
      else if (apps[scrollIndex].state == 3) lcd.print(" [DEL]");
      else                                   lcd.print(" [OFF]");
      lcd.setCursor(0, 1);
      if (apps[scrollIndex].state == 0) lcd.print("ON?   B1=Y B2=N");
      else                              lcd.print("OFF?  B1=Y B2=N");
      break;
  }
}

// ================= State Machine =================
void handleConfirm() {
  switch (currentMenuState) {

    case HOME_PAGE:
      currentMenuState = APPLIANCE_LIST;
      break;

    case APPLIANCE_LIST:
      if (apps[scrollIndex].state == 0) {
        currentMenuState = APPLIANCE_TOGGLE_CONFIRM;
      } else {
        actionIndex = 2;
        currentMenuState = APPLIANCE_ACTION_SELECT;
      }
      break;

    case APPLIANCE_ACTION_SELECT:
      if (actionIndex == 0) {
        currentMenuState = APPLIANCE_SCHEDULE_SELECT;
        break;
      } else if (actionIndex == 1) {
        apps[scrollIndex].state = 2;
        sendCommandToR4(R4_DEVICE[scrollIndex], "on");
        sendCommandToR4("mode", "eco");
        switchToState(ECO_MODE);
      } else {
        apps[scrollIndex].state = 0;
        sendCommandToR4(R4_DEVICE[scrollIndex], "off");
        if (currentState == ECO_MODE) {
          bool anyManaged = false;
          for (int i = 0; i < 3; i++) {
            if (apps[i].state == 2 || apps[i].state == 3) { anyManaged = true; break; }
          }
          if (!anyManaged) {
            sendCommandToR4("mode", "normal");
            switchToState(NORMAL);
          }
        }
      }
      currentMenuState = APPLIANCE_LIST;
      break;

    case APPLIANCE_SCHEDULE_SELECT:
      apps[scrollIndex].state = 3;
      apps[scrollIndex].scheduleIndex = timeScrollIndex;
      smartDelayUntil = scheduleTimes[timeScrollIndex];
      if (smartDelayUntil.startsWith("Pause")) smartDelayPauseStart = millis();
      sendCommandToR4(R4_DEVICE[scrollIndex], "off");
      switchToState(ECO_MODE);
      currentMenuState = HOME_PAGE;
      break;

    case APPLIANCE_TOGGLE_CONFIRM:
      apps[scrollIndex].state = 1;
      sendCommandToR4(R4_DEVICE[scrollIndex], "on");
      currentMenuState = APPLIANCE_LIST;
      break;

    case ALERT_PROMPT:
      currentMenuState = MODE_SELECT;
      break;

    case CANCEL_PROMPT:
      sendCommandToR4("mode", "normal");
      syncDeviceStatesToR4();
      switchToState(NORMAL);
      currentMenuState = HOME_PAGE;
      break;

    case MODE_SELECT:
      if (modeIndex == 0) {
        currentMenuState = GLOBAL_SCHEDULE;
      } else {
        if (apps[peakApplianceIndex].state == 1) {
          apps[peakApplianceIndex].state = 2;
          apps[peakApplianceIndex].scheduleIndex = -1;
        }
        sendCommandToR4("mode", "eco");
        switchToState(ECO_MODE);
        currentMenuState = HOME_PAGE;
      }
      break;

    case MODE_CANCEL_PROMPT:
      enterAlertPrompt();
      break;

    case GLOBAL_SCHEDULE:
      if (apps[peakApplianceIndex].state != 0) {
        apps[peakApplianceIndex].state = 3;
        apps[peakApplianceIndex].scheduleIndex = timeScrollIndex;
      }
      smartDelayUntil = scheduleTimes[timeScrollIndex];
      if (smartDelayUntil.startsWith("Pause")) smartDelayPauseStart = millis();
      sendCommandToR4(R4_DEVICE[peakApplianceIndex], "off");
      switchToState(ECO_MODE);
      currentMenuState = HOME_PAGE;
      break;
  }
  updateLCDDisplay();
}

void handleCancel() {
  switch (currentMenuState) {

    case ALERT_PROMPT:
      currentMenuState = CANCEL_PROMPT;
      break;

    case CANCEL_PROMPT:
      enterAlertPrompt();
      break;

    case MODE_SELECT:
      currentMenuState = MODE_CANCEL_PROMPT;
      break;

    case MODE_CANCEL_PROMPT:
      currentMenuState = MODE_SELECT;
      break;

    case GLOBAL_SCHEDULE:
      currentMenuState = MODE_SELECT;
      break;

    case APPLIANCE_LIST:
      currentMenuState = HOME_PAGE;
      break;

    case APPLIANCE_ACTION_SELECT:
      currentMenuState = APPLIANCE_LIST;
      break;

    case APPLIANCE_SCHEDULE_SELECT:
      currentMenuState = APPLIANCE_ACTION_SELECT;
      break;

    case APPLIANCE_TOGGLE_CONFIRM:
      currentMenuState = APPLIANCE_LIST;
      break;
  }
  updateLCDDisplay();
}

// ================= Input Scanning =================
void checkPhysicalUI() {
  int c1 = digitalRead(BTN_1_PIN);
  int c2 = digitalRead(BTN_2_PIN);
  int pot = analogRead(POT_PIN);

  if (c1 == LOW && lastBtn1State == HIGH && millis() - lastBtn1Press > 150) {
    handleConfirm();
    lastBtn1Press = millis();
  }
  lastBtn1State = c1;

  if (c2 == HIGH) {
    if (!btn2IsHolding) {
      btn2PressedTime = millis();
      btn2IsHolding = true;
    } else if (millis() - btn2PressedTime > RESET_HOLD_TIME) {
      if (isAtDefaultHome()) {
        sendCommandToR4("reset", "now");
        delay(300);
        ESP.restart();
      } else {
        for (int i = 0; i < 3; i++) apps[i].state = 1;
        smartDelayUntil = "";
        sendCommandToR4("mode", "normal");
        syncDeviceStatesToR4();
        switchToState(NORMAL);
        currentMenuState = HOME_PAGE;
        updateLCDDisplay();
        btn2IsHolding = false;
        while (digitalRead(BTN_2_PIN) == HIGH) ;
      }
    }
  } else {
    if (btn2IsHolding) {
      if (millis() - btn2PressedTime < HOLD_DETECT_MS) handleCancel();
      btn2IsHolding = false;
      updateLCDDisplay();
    }
  }

  if (abs(pot - lastStablePotRaw) > 30) {
    lastStablePotRaw = pot;
    if (currentMenuState == APPLIANCE_LIST) {
      scrollIndex = constrain(map(pot, 0, 4096, 0, 3), 0, 2);
    } else if (currentMenuState == APPLIANCE_ACTION_SELECT) {
      actionIndex = constrain(map(pot, 0, 4096, 0, 3), 0, 2);
    } else if (currentMenuState == APPLIANCE_SCHEDULE_SELECT) {
      timeScrollIndex = constrain(map(pot, 0, 4096, 0, NUM_TIMES), 0, NUM_TIMES - 1);
    } else if (currentMenuState == MODE_SELECT) {
      int target = (pot >= 2048) ? 1 : 0;
      if (target != modeIndex) {
        if (target == 1 && pot > 2148) modeIndex = 1;
        else if (target == 0 && pot < 1948) modeIndex = 0;
      }
    } else if (currentMenuState == GLOBAL_SCHEDULE) {
      timeScrollIndex = constrain(map(pot, 0, 4096, 0, NUM_TIMES), 0, NUM_TIMES - 1);
    }
    updateLCDDisplay();
  }
}

// ================= Setup / Loop =================
void setup() {
  Serial.begin(115200);
  pinMode(LED_R, OUTPUT); pinMode(LED_Y, OUTPUT); pinMode(LED_G, OUTPUT);
  pinMode(BTN_1_PIN, INPUT_PULLUP);
  pinMode(BTN_2_PIN, INPUT);

  Wire.begin(32, 33);
  lcd.begin(16, 2);
  setupRGB_v4();

  simBootMillis = millis();
  randomSeed(analogRead(POT_PIN));
  switchToState(NORMAL);
  updateLCDDisplay();

  // ── WiFi: STA first so AP starts on the correct channel ──────
  // If AP starts before STA connects, the ESP32 switches AP channel
  // when STA joins — which kicks the R4 off ESP32_AP.
  WiFi.mode(WIFI_AP_STA);
  esp_wifi_set_ps(WIFI_PS_NONE);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 3000) delay(200);
  if (WiFi.status() == WL_CONNECTED) {
    wifiReady = true;
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER);
    Serial.println("STA connected. IP: " + WiFi.localIP().toString());
  } else {
    Serial.println("STA failed — running offline");
  }

  // AP now starts on the same channel as STA — no switch will occur
  WiFi.softAP(AP_SSID, AP_PASS);
  r4Server.begin();
  Serial.println("AP started: " + String(AP_SSID) + "  ch=" + String(WiFi.channel()));
  Serial.println("R4 TCP server on port " + String(TCP_PORT));

  flutterServer.begin();
  Serial.println("Flutter TCP server on port " + String(FLUTTER_TCP_PORT));

  updateLCDDisplay();
}

void loop() {
  // ── R4 TCP: accept new connection ────────────────────────────
  if (!r4Client || !r4Client.connected()) {
    WiFiClient c = r4Server.accept();
    if (c) {
      r4Client = c;
      Serial.println("[R4] Connected — syncing device states");
      delay(100);
      syncDeviceStatesToR4();
    }
  }

  // ── R4 TCP: receive power data (non-blocking) ────────────────
  while (r4Client && r4Client.connected() && r4Client.available()) {
    char c = r4Client.read();
    if (c == '\n') {
      r4RxBuffer.trim();
      if (r4RxBuffer.length()) onR4Data(r4RxBuffer);
      r4RxBuffer = "";
      break;
    }
    r4RxBuffer += c;
  }

  // ── Flutter TCP: accept new connection ───────────────────────
  if (!flutterClient || !flutterClient.connected()) {
    WiFiClient c = flutterServer.accept();
    if (c) {
      flutterClient = c;
      Serial.println("[Flutter] App connected — sending status snapshot");
      delay(100);
      sendStatusToFlutter();
    }
  }

  // ── Flutter TCP: receive commands (non-blocking) ─────────────
  while (flutterClient && flutterClient.connected() && flutterClient.available()) {
    char c = flutterClient.read();
    if (c == '\n') {
      flutterRxBuffer.trim();
      if (flutterRxBuffer.length()) onFlutterCommand(flutterRxBuffer);
      flutterRxBuffer = "";
      break;
    }
    flutterRxBuffer += c;
  }

  // ── Smart delay auto-resume ───────────────────────────────────
  if (currentState == ECO_MODE && smartDelayUntil.length() > 0) {
    bool resume = false;
    if (smartDelayUntil.startsWith("Pause")) {
      resume = (millis() - smartDelayPauseStart >= PAUSE_DEMO_MS);
    } else {
      int col = smartDelayUntil.indexOf(':');
      if (col > 0) {
        int tH = smartDelayUntil.substring(0, col).toInt();
        int tM = smartDelayUntil.substring(col + 1).toInt();
        resume = (getCurrentHour() == tH && getCurrentMinute() >= tM);
      }
    }
    if (resume) {
      for (int i = 0; i < 3; i++) if (apps[i].state == 3) apps[i].state = 1;
      smartDelayUntil = "";
      bool anyEco = false;
      for (int i = 0; i < 3; i++) if (apps[i].state == 2) { anyEco = true; break; }
      if (anyEco) {
        sendCommandToR4("mode", "eco");
        syncDeviceStatesToR4();
      } else {
        sendCommandToR4("mode", "normal");
        syncDeviceStatesToR4();
        switchToState(NORMAL);
      }
      currentMenuState = HOME_PAGE;
      updateLCDDisplay();
    }
  }

  // ── Existing loop logic (unchanged) ──────────────────────────
  checkPhysicalUI();
  unsigned long ms = millis();

  if (currentState == NORMAL && currentMenuState == HOME_PAGE && ms - lastStateChange > 15000) {
    peakApplianceIndex = findPeakAppliance();
    switchToState(PEAK_ALERT);
    currentMenuState = ALERT_INTRO;
    alertIntroStart = ms;
    updateLCDDisplay();
  }

  if (currentMenuState == ALERT_INTRO
      && ms - alertIntroStart > ALERT_INTRO_DURATION) {
    enterAlertPrompt();
    updateLCDDisplay();
  }

  if (currentMenuState == ALERT_PROMPT && !btn2IsHolding
      && ms - lastAlertToggle > ALERT_PHASE_DURATION) {
    lastAlertToggle = ms;
    alertShowSwipe = !alertShowSwipe;
    updateLCDDisplay();
  }

  if (currentMenuState == ALERT_PROMPT) {
    pinMode(ULTRA_SIG, OUTPUT);
    digitalWrite(ULTRA_SIG, LOW);  delayMicroseconds(2);
    digitalWrite(ULTRA_SIG, HIGH); delayMicroseconds(10);
    digitalWrite(ULTRA_SIG, LOW);
    pinMode(ULTRA_SIG, INPUT);
    long dur = pulseIn(ULTRA_SIG, HIGH, 20000);
    if (dur > 0 && (dur / 58) < 30) {
      for (int i = 0; i < 3; i++) {
        setRGB_v4(0, 0, 0);   delay(120);
        setRGB_v4(255, 0, 0); delay(120);
      }
      currentMenuState = MODE_SELECT;
      updateLCDDisplay();
      delay(500);
    }
  }

  if (currentState == ECO_MODE && currentMenuState == APPLIANCE_LIST) {
    refreshEcoFlicker();
    if (apps[scrollIndex].state == 2 && ms - lastLcdUpdate > 1000) {
      lastLcdUpdate = ms;
      updateLCDDisplay();
    }
  }

  if (btn2IsHolding && !isAtDefaultHome()
      && ms - btn2PressedTime > HOLD_DETECT_MS
      && ms - lastLcdUpdate > 200) {
    lastLcdUpdate = ms;
    updateLCDDisplay();
  }

  if (currentMenuState == HOME_PAGE && !btn2IsHolding
      && ms - lastHomeToggle > 2000) {
    lastHomeToggle = ms;
    homeShowAltScreen = !homeShowAltScreen;
    updateLCDDisplay();
  }

  delay(10);
}
