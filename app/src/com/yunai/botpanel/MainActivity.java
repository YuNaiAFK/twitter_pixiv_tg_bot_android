package com.yunai.botpanel;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Controls the bot through the panel's HTTP API on 127.0.0.1.
 *
 * <h2>Why it talks to the panel and not to Termux</h2>
 *
 * Starting the bot means running `run-bot.sh` inside Termux, which owns its own environment. An
 * ordinary app cannot do that: `com.termux.RUN_COMMAND` needs `allow-external-apps=true` in
 * Termux's properties, and reading Termux's log file directly is impossible because
 * `/data/data/com.termux/files/home` is not readable by another package. So the panel - which
 * already runs inside Termux and already exposes exactly these actions - is the interface.
 *
 * The consequence is stated in the UI rather than hidden: if the panel is not running, this app
 * cannot do anything, and it says so instead of showing an empty screen that looks broken.
 *
 * <h2>No dependencies</h2>
 *
 * Framework classes only - no AppCompat, no Material, no JSON library beyond `org.json`, which
 * ships with Android. That keeps the APK small and, more usefully here, means it builds with
 * `aapt2`/`javac`/`d8` alone instead of needing Gradle and the Android Gradle Plugin.
 *
 * The UI is built in code for the same reason: no layout XML means nothing to compile and no
 * `R` class beyond the icon.
 */
public class MainActivity extends Activity {

    private static final String DEFAULT_BASE = "http://127.0.0.1:8090";
    /** How often the status and the log refresh while the screen is in front. */
    private static final int POLL_MS = 4000;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService pool = Executors.newFixedThreadPool(3);

    private String base = DEFAULT_BASE;

    private TextView botValue, botDetail;
    private TextView srvValue, srvDetail;
    private TextView pxyValue, pxyDetail;
    private TextView diskValue, diskDetail;
    private TextView logView, logMeta, bannerText;
    private View banner;
    private Button liveButton;

    private boolean live = true;
    private long lastLogSize = -1;
    private volatile boolean destroyed = false;

    // ------------------------------------------------------------------ lifecycle

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildUi());

        // A saved base lets the app be pointed at a different port without a rebuild; it is
        // restored from the instance state rather than stored, because one process lifetime is
        // the whole of its usefulness.
        if (savedInstanceState != null) {
            String saved = savedInstanceState.getString("base");
            if (saved != null && !saved.isEmpty()) base = saved;
        }

        bannerText.setText("連線中…  " + base);
        refreshStatus();
        loadLog(true);
        ui.postDelayed(this::pollOnce, POLL_MS);
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putString("base", base);
    }

    @Override
    protected void onDestroy() {
        destroyed = true;
        ui.removeCallbacksAndMessages(null);
        pool.shutdownNow();
        super.onDestroy();
    }

    // ------------------------------------------------------------------ UI construction

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private TextView label(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(12f);
        view.setTextColor(Color.parseColor("#8b93a7"));
        view.setPadding(0, dp(2), 0, 0);
        return view;
    }

    private TextView value(String text, int colour, float size) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(colour);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        return view;
    }

    private TextView detail(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(11f);
        view.setTextColor(Color.parseColor("#8b93a7"));
        view.setTypeface(Typeface.MONOSPACE);
        return view;
    }

    /** A rounded card. Built from a GradientDrawable so there is no drawable XML to compile. */
    private LinearLayout card(TextView[] outValue, TextView[] outDetail, String title, String colour) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(13), dp(11), dp(13), dp(11));

        android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable();
        bg.setColor(Color.parseColor("#171a21"));
        bg.setCornerRadius(dp(12));
        bg.setStroke(dp(1), Color.parseColor("#272c37"));
        box.setBackground(bg);

        box.addView(label(title));
        TextView v = value("—", Color.parseColor(colour), 17f);
        box.addView(v);
        TextView d = detail("—");
        box.addView(d);

        outValue[0] = v;
        outDetail[0] = d;
        return box;
    }

    private Button action(String text, boolean primary, boolean danger, Runnable onClick) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextSize(14f);
        button.setAllCaps(false);
        button.setTypeface(Typeface.DEFAULT_BOLD);

        android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable();
        if (danger) {
            bg.setColor(Color.parseColor("#4a1f1e"));
            bg.setStroke(dp(1), Color.parseColor("#7d2f2c"));
        } else if (primary) {
            bg.setColor(Color.parseColor("#1d3a6b"));
            bg.setStroke(dp(1), Color.parseColor("#2c56a0"));
        } else {
            bg.setColor(Color.parseColor("#1e222b"));
            bg.setStroke(dp(1), Color.parseColor("#272c37"));
        }
        bg.setCornerRadius(dp(11));
        button.setBackground(bg);
        button.setTextColor(Color.parseColor("#e6e9ef"));
        button.setPadding(0, dp(12), 0, dp(12));
        button.setOnClickListener(v -> onClick.run());

        LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        params.setMargins(dp(3), dp(3), dp(3), dp(3));
        button.setLayoutParams(params);
        return button;
    }

    private LinearLayout row(Button... buttons) {
        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        for (Button b : buttons) line.addView(b);
        return line;
    }

    private TextView section(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(12f);
        view.setTextColor(Color.parseColor("#8b93a7"));
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setPadding(dp(3), dp(16), dp(3), dp(6));
        return view;
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0f1115"));
        root.setPadding(dp(12), dp(14), dp(12), dp(14));

        // A banner that says why the app cannot act, rather than leaving the buttons looking
        // broken. Hidden while the panel answers.
        banner = new LinearLayout(this);
        ((LinearLayout) banner).setOrientation(LinearLayout.VERTICAL);
        ((LinearLayout) banner).setPadding(dp(12), dp(10), dp(12), dp(10));
        android.graphics.drawable.GradientDrawable bannerBg = new android.graphics.drawable.GradientDrawable();
        bannerBg.setColor(Color.parseColor("#3a2a12"));
        bannerBg.setCornerRadius(dp(10));
        bannerBg.setStroke(dp(1), Color.parseColor("#7a5a1f"));
        banner.setBackground(bannerBg);
        bannerText = new TextView(this);
        bannerText.setTextSize(12.5f);
        bannerText.setTextColor(Color.parseColor("#ffd479"));
        ((LinearLayout) banner).addView(bannerText);
        banner.setVisibility(View.GONE);
        root.addView(banner);

        root.addView(section("狀態"));

        TextView[] v = new TextView[1];
        TextView[] d = new TextView[1];

        LinearLayout firstRow = new LinearLayout(this);
        firstRow.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams half =
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        half.setMargins(dp(3), dp(3), dp(3), dp(3));

        LinearLayout botCard = card(v, d, "機器人", "#e6e9ef");
        botValue = v[0]; botDetail = d[0];
        botCard.setLayoutParams(half);
        LinearLayout srvCard = card(v, d, "自架伺服器", "#e6e9ef");
        srvValue = v[0]; srvDetail = d[0];
        srvCard.setLayoutParams(half);
        firstRow.addView(botCard);
        firstRow.addView(srvCard);
        root.addView(firstRow);

        LinearLayout secondRow = new LinearLayout(this);
        secondRow.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout pxyCard = card(v, d, "梯子", "#e6e9ef");
        pxyValue = v[0]; pxyDetail = d[0];
        pxyCard.setLayoutParams(half);
        LinearLayout diskCard = card(v, d, "磁碟 / 快取", "#e6e9ef");
        diskValue = v[0]; diskDetail = d[0];
        diskCard.setLayoutParams(half);
        secondRow.addView(pxyCard);
        secondRow.addView(diskCard);
        root.addView(secondRow);

        root.addView(section("機器人"));
        root.addView(row(
                action("啟動", true, false, () -> act("/api/bot/start", false)),
                action("關閉", false, true, () -> confirm("關閉機器人？", "/api/bot/stop")),
                action("重啟", false, false, () -> act("/api/bot/restart", false))));

        root.addView(section("伺服器（2000 MB 上傳）"));
        root.addView(row(
                action("啟動", true, false, () -> act("/api/server/start", false)),
                action("關閉", false, true, () -> confirm("關閉伺服器？機器人將無法上傳大檔案。", "/api/server/stop")),
                action("重啟", false, false, () -> act("/api/server/restart", false))));

        root.addView(section("記錄"));
        LinearLayout logBar = new LinearLayout(this);
        logBar.setOrientation(LinearLayout.HORIZONTAL);
        logBar.setGravity(Gravity.CENTER_VERTICAL);
        liveButton = action("暫停更新", false, false, this::toggleLive);
        logBar.addView(liveButton);
        Button reload = action("重新載入", false, false, () -> loadLog(true));
        logBar.addView(reload);
        logMeta = new TextView(this);
        logMeta.setTextSize(11f);
        logMeta.setTextColor(Color.parseColor("#8b93a7"));
        logMeta.setTypeface(Typeface.MONOSPACE);
        logMeta.setPadding(dp(8), 0, 0, 0);
        logBar.addView(logMeta);
        root.addView(logBar);

        logView = new TextView(this);
        logView.setTextSize(10.5f);
        logView.setTypeface(Typeface.MONOSPACE);
        logView.setTextColor(Color.parseColor("#cdd3df"));
        logView.setPadding(dp(11), dp(10), dp(11), dp(10));
        logView.setMovementMethod(new ScrollingMovementMethod());
        logView.setTextIsSelectable(true);
        android.graphics.drawable.GradientDrawable logBg = new android.graphics.drawable.GradientDrawable();
        logBg.setColor(Color.parseColor("#0a0c10"));
        logBg.setCornerRadius(dp(12));
        logBg.setStroke(dp(1), Color.parseColor("#272c37"));
        logView.setBackground(logBg);
        logView.setText("載入中…");

        // A fixed-height scroller: the log must scroll inside its own box rather than pushing the
        // buttons off the screen, which is what happens when it grows the page.
        ScrollView logScroll = new ScrollView(this);
        logScroll.addView(logView);
        LinearLayout.LayoutParams logParams =
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(240));
        logParams.setMargins(dp(3), dp(3), dp(3), dp(3));
        logScroll.setLayoutParams(logParams);
        root.addView(logScroll);

        root.addView(section("工具"));
        root.addView(row(
                action("清除快取", false, false, () -> confirm("清除下載快取與解析記錄？", "/api/cache/clear")),
                action("面板網頁", false, false, this::openInBrowser),
                action("重新整理", false, false, () -> {
                    refreshStatus();
                    loadLog(true);
                })));

        TextView note = new TextView(this);
        note.setTextSize(11.5f);
        note.setTextColor(Color.parseColor("#8b93a7"));
        note.setPadding(dp(3), dp(16), dp(3), 0);
        note.setText("按鈕執行的是 Termux 裡既有的 run-bot.sh 與 run-server.sh。\n"
                + "這個 app 需要控制面板在執行中：Termux 裡執行 bash control/run-panel.sh start");
        root.addView(note);

        ScrollView page = new ScrollView(this);
        page.setBackgroundColor(Color.parseColor("#0f1115"));
        page.addView(root);
        return page;
    }

    // ------------------------------------------------------------------ polling

    /**
     * One refresh, then schedule the next.
     *
     * <h2>Why a method and not a field holding the Runnable</h2>
     *
     * **No anonymous inner classes in this app.** d8 8.2.2 - the dexer in build-tools 34.0.0 -
     * crashes on the class file javac 21 generates for one:
     *
     *     Error in .../MainActivity$1.class:
     *     java.lang.NullPointerException: Cannot invoke "String.length()" because "<parameter1>" is null
     *
     * That is not specific to this class: a five-line `new Runnable() { ... }` reproduces it. A
     * lambda compiles to `invokedynamic` with no `$1` class file, and a *named* nested class is
     * handled fine - only the anonymous form breaks. All three were built to confirm that.
     *
     * The obvious lambda - a field initialised with `() -> { ... ui.postDelayed(poller, ...) }` -
     * does not compile either: Java rejects a field initialiser that refers to the field being
     * initialised ("cannot reference itself in initializer"). A method reference has neither
     * problem: `this::pollOnce` makes no class file and refers to nothing unfinished.
     */
    private void pollOnce() {
        if (destroyed) return;
        refreshStatus();
        if (live) loadLog(false);
        ui.postDelayed(this::pollOnce, POLL_MS);
    }

    private void toggleLive() {
        live = !live;
        liveButton.setText(live ? "暫停更新" : "開始更新");
        if (live) loadLog(true);
    }

    // ------------------------------------------------------------------ http

    /** One request. Returns the parsed body, or throws with something worth showing. */
    private JSONObject request(String path, boolean post) throws Exception {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(base + path).openConnection();
            // Timeouts matter more than usual here: the panel answers in milliseconds, so a slow
            // one means it is gone, and waiting 30 s per poll would freeze the screen.
            conn.setConnectTimeout(3000);
            conn.setReadTimeout(post ? 90000 : 15000);
            conn.setRequestMethod(post ? "POST" : "GET");
            if (post) {
                conn.setDoOutput(true);
                conn.setRequestProperty("Content-Type", "application/json");
                try (OutputStream out = conn.getOutputStream()) {
                    out.write("{}".getBytes(StandardCharsets.UTF_8));
                }
            }
            int code = conn.getResponseCode();
            InputStream stream = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (stream == null) throw new Exception("HTTP " + code + " with no body");
            StringBuilder body = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) body.append(line).append('\n');
            }
            return new JSONObject(body.toString());
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private void showBanner(String text) {
        bannerText.setText(text);
        banner.setVisibility(View.VISIBLE);
    }

    private void hideBanner() {
        banner.setVisibility(View.GONE);
    }

    private void refreshStatus() {
        pool.execute(() -> {
            try {
                JSONObject s = request("/api/status", false);
                if (destroyed) return;
                final JSONObject bot = s.getJSONObject("bot");
                final JSONObject srv = s.getJSONObject("server");
                final JSONObject pxy = s.getJSONObject("proxy");

                // Built here rather than inside the runnable so a JSONException cannot leave the
                // UI half-updated.
                final boolean botUp = bot.getBoolean("running");
                final String botPid = bot.isNull("pid") ? "—" : String.valueOf(bot.getInt("pid"));
                final String botHow = bot.optString("how", "");
                final boolean srvUp = srv.getBoolean("running");
                final String srvHow = srv.optString("how", "");
                final boolean pxyOk = pxy.optBoolean("listening");
                final boolean pxySet = pxy.optBoolean("configured");
                final String pxyUrl = pxy.optString("url", "");
                final String free = s.optJSONObject("disk") == null ? "—"
                        : s.getJSONObject("disk").optString("free_h", "—");
                final String cache = s.optString("cache_h", "—");

                ui.post(() -> {
                    if (destroyed) return;
                    hideBanner();

                    botValue.setText(botUp ? "執行中" : "已停止");
                    botValue.setTextColor(Color.parseColor(botUp ? "#35c07a" : "#e5534b"));
                    botDetail.setText(botUp ? "pid " + botPid + "（" + botHow + "）" : botHow);

                    srvValue.setText(srvUp ? "執行中" : "已停止");
                    srvValue.setTextColor(Color.parseColor(srvUp ? "#35c07a" : "#e5534b"));
                    srvDetail.setText(srvUp ? srvHow : srvHow);

                    if (!pxySet) {
                        pxyValue.setText("未設定");
                        pxyValue.setTextColor(Color.parseColor("#e5534b"));
                    } else if (pxyOk) {
                        pxyValue.setText("可用");
                        pxyValue.setTextColor(Color.parseColor("#35c07a"));
                    } else {
                        // The failure that looks like a broken bot while the bot is fine.
                        pxyValue.setText("無回應");
                        pxyValue.setTextColor(Color.parseColor("#e8b23a"));
                    }
                    pxyDetail.setText(pxyUrl.isEmpty() ? "—" : pxyUrl);

                    diskValue.setText(free + " 可用");
                    diskValue.setTextColor(Color.parseColor("#e6e9ef"));
                    diskDetail.setText("快取 " + cache);
                });
            } catch (Exception exc) {
                if (destroyed) return;
                final String message = describe(exc);
                ui.post(() -> {
                    if (destroyed) return;
                    botValue.setText("無法連線");
                    botValue.setTextColor(Color.parseColor("#e5534b"));
                    botDetail.setText(message);
                    srvValue.setText("—");
                    pxyValue.setText("—");
                    diskValue.setText("—");
                    // The single most likely reason, named outright, because "connection refused"
                    // does not tell anyone that the panel has to be started first.
                    showBanner("控制面板沒有回應（" + base + "）。\n"
                            + "在 Termux 執行：bash control/run-panel.sh start");
                });
            }
        });
    }

    private String describe(Exception exc) {
        String message = exc.getMessage();
        if (message == null || message.isEmpty()) message = exc.getClass().getSimpleName();
        return message;
    }

    private void loadLog(boolean force) {
        pool.execute(() -> {
            try {
                JSONObject body = request("/api/log?lines=300", false);
                final JSONArray lines = body.optJSONArray("lines");
                final long size = body.optLong("size", 0);
                // Skip the redraw when nothing changed: replacing the text resets the scroll
                // position, which makes the log unusable while it is being read.
                if (!force && size == lastLogSize) return;
                lastLogSize = size;

                StringBuilder text = new StringBuilder();
                if (lines != null) {
                    for (int i = 0; i < lines.length(); i++) {
                        text.append(lines.optString(i)).append('\n');
                    }
                }
                final String rendered = text.length() == 0 ? "（沒有記錄）" : text.toString();
                ui.post(() -> {
                    if (destroyed) return;
                    logView.setText(rendered);
                    logMeta.setText(bytes(size));
                    // Jump to the newest line, which is what anyone watching wants to see.
                    if (logView.getParent() instanceof ScrollView) {
                        final ScrollView scroller = (ScrollView) logView.getParent();
                        scroller.post(() -> scroller.fullScroll(View.FOCUS_DOWN));
                    }
                });
            } catch (Exception ignored) {
                // The banner already reports an unreachable panel; repeating it here would
                // overwrite the log with the same message every few seconds.
            }
        });
    }

    private static String bytes(long n) {
        if (n < 1024) return n + " B";
        String[] units = {"KB", "MB", "GB", "TB"};
        double value = n;
        int unit = -1;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return String.format(Locale.US, "%.1f %s", value, units[unit]);
    }

    // ------------------------------------------------------------------ actions

    private void confirm(String question, String path) {
        new AlertDialog.Builder(this)
                .setMessage(question)
                .setPositiveButton("確定", (d, w) -> act(path, false))
                .setNegativeButton("取消", null)
                .show();
    }

    private void act(String path, boolean unused) {
        Toast.makeText(this, "執行中…", Toast.LENGTH_SHORT).show();
        pool.execute(() -> {
            try {
                JSONObject result = request(path, true);
                final boolean ok = result.optBoolean("ok");
                String output = result.optString("stdout", "") + result.optString("stderr", "");
                output = output.trim();
                if (output.isEmpty()) output = result.optString("error", "");
                final String shown = output.isEmpty() ? (ok ? "完成" : "失敗，沒有輸出")
                        : lastLines(output, 6);
                ui.post(() -> {
                    if (destroyed) return;
                    Toast.makeText(this, (ok ? "✓ " : "✗ ") + shown,
                            ok ? Toast.LENGTH_SHORT : Toast.LENGTH_LONG).show();
                    refreshStatus();
                    loadLog(true);
                });
            } catch (Exception exc) {
                final String message = describe(exc);
                ui.post(() -> Toast.makeText(this,
                        "無法連線到控制面板：" + message, Toast.LENGTH_LONG).show());
            }
        });
    }

    private static String lastLines(String text, int count) {
        String[] lines = text.split("\n");
        int start = Math.max(0, lines.length - count);
        StringBuilder out = new StringBuilder();
        for (int i = start; i < lines.length; i++) {
            String line = lines[i].trim();
            if (!line.isEmpty()) out.append(line).append('\n');
        }
        return out.toString().trim();
    }

    private void openInBrowser() {
        try {
            startActivity(new android.content.Intent(
                    android.content.Intent.ACTION_VIEW, android.net.Uri.parse(base + "/")));
        } catch (Exception exc) {
            Toast.makeText(this, "沒有瀏覽器可以開啟", Toast.LENGTH_SHORT).show();
        }
    }
}
