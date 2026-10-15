package com.yunai.botpanel;

import android.app.Activity;
import android.content.Intent;
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
    private static final String TAG = "BotPanel";

    /**
     * Termux's package and the command service it exposes for other apps.
     *
     * The service is declared with `permission com.termux.permission.RUN_COMMAND`, which this
     * app requests, and Termux additionally requires `allow-external-apps=true` in its own
     * properties before it will act on the intent. Both are checked; see startServices().
     */
    private static final String TERMUX_PACKAGE = "com.termux";
    private static final String TERMUX_SERVICE = "com.termux.app.RunCommandService";
    private static final String ACTION_RUN_COMMAND = "com.termux.RUN_COMMAND";
    private static final String PERMISSION_RUN_COMMAND = "com.termux.permission.RUN_COMMAND";

    /** Where the project lives inside Termux. Matches what the installer creates. */
    private static final String TERMUX_HOME = "/data/data/com.termux/files/home";
    private static final String TERMUX_BIN = "/data/data/com.termux/files/usr/bin";
    private static final String PROJECT_DIR = TERMUX_HOME + "/twitter_pixiv_tg_bot";

    /** Request codes for the two runtime permissions. */
    private static final int REQ_RUN_COMMAND = 1001;

    /** What the card's button does next. */
    private static final int ACTION_NONE = 0;
    private static final int ACTION_START = 1;
    private static final int ACTION_TOGGLE_HELP = 2;
    private static final int ACTION_RETRY = 3;
    /** How often the status and the log refresh while the screen is in front. */
    private static final int POLL_MS = 4000;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService pool = Executors.newFixedThreadPool(3);

    private String base = DEFAULT_BASE;

    private TextView botValue, botDetail;
    private TextView srvValue, srvDetail;
    private TextView pxyValue, pxyDetail;
    private TextView diskValue, diskDetail;
    private TextView logView, logMeta, bannerText, bannerTitle, bannerDetail;
    private View banner;
    private Button liveButton, bannerButton;
    /** What the banner's button should do next; see onBannerButton(). */
    private int bannerAction = ACTION_NONE;
    /** True while the app is waiting for the services it just asked Termux to start. */
    private volatile boolean waitingForStart = false;

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

        // The "start everything" card.
        //
        // It exists because of a circular dependency: this app talks to the control panel, and
        // the panel is a Termux process that someone has to start. Without this, the app is
        // useless until the user opens a terminal and types a command - which is the whole thing
        // it is meant to avoid.
        //
        // The button sends com.termux.RUN_COMMAND, asking Termux to run scripts/start-all.sh.
        // Two things must be true, and the card checks and reports both rather than failing
        // silently:
        //
        //   1. this app holds com.termux.permission.RUN_COMMAND (requested at runtime)
        //   2. Termux's properties say `allow-external-apps=true`, and Termux has been restarted
        //      since - written by scripts/enable-external-apps.sh
        //
        // If either is missing the intent is dropped with no error at all. A button that
        // appeared to do nothing would be the worst possible outcome, so the manual command is
        // always one tap away rather than hidden behind a failure.
        banner = new LinearLayout(this);
        ((LinearLayout) banner).setOrientation(LinearLayout.VERTICAL);
        ((LinearLayout) banner).setPadding(dp(13), dp(12), dp(13), dp(12));
        android.graphics.drawable.GradientDrawable bannerBg = new android.graphics.drawable.GradientDrawable();
        bannerBg.setColor(Color.parseColor("#3a2a12"));
        bannerBg.setCornerRadius(dp(10));
        bannerBg.setStroke(dp(1), Color.parseColor("#7a5a1f"));
        banner.setBackground(bannerBg);

        bannerTitle = new TextView(this);
        bannerTitle.setTextSize(15f);
        bannerTitle.setTypeface(Typeface.DEFAULT_BOLD);
        bannerTitle.setTextColor(Color.parseColor("#ffd479"));
        ((LinearLayout) banner).addView(bannerTitle);

        bannerText = new TextView(this);
        bannerText.setTextSize(12.5f);
        bannerText.setTextColor(Color.parseColor("#e8d9b0"));
        bannerText.setPadding(0, dp(4), 0, 0);
        ((LinearLayout) banner).addView(bannerText);

        bannerButton = new Button(this);
        bannerButton.setTextSize(14f);
        bannerButton.setAllCaps(false);
        bannerButton.setTypeface(Typeface.DEFAULT_BOLD);
        android.graphics.drawable.GradientDrawable btnBg = new android.graphics.drawable.GradientDrawable();
        btnBg.setColor(Color.parseColor("#8a5a12"));
        btnBg.setCornerRadius(dp(10));
        btnBg.setStroke(dp(1), Color.parseColor("#c08a30"));
        bannerButton.setBackground(btnBg);
        bannerButton.setTextColor(Color.parseColor("#fff4dd"));
        bannerButton.setPadding(0, dp(13), 0, dp(13));
        LinearLayout.LayoutParams btnParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        btnParams.setMargins(0, dp(10), 0, 0);
        bannerButton.setLayoutParams(btnParams);
        bannerButton.setOnClickListener(v -> onBannerButton());
        ((LinearLayout) banner).addView(bannerButton);

        bannerDetail = new TextView(this);
        bannerDetail.setTextSize(11f);
        bannerDetail.setTypeface(Typeface.MONOSPACE);
        bannerDetail.setTextColor(Color.parseColor("#cbb98d"));
        bannerDetail.setPadding(0, dp(9), 0, 0);
        bannerDetail.setTextIsSelectable(true);
        bannerDetail.setVisibility(View.GONE);
        ((LinearLayout) banner).addView(bannerDetail);

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

        // **A fixed-height TextView that scrolls itself, rather than a TextView inside a
        // ScrollView.** The nested version looked right but never followed the tail: fullScroll()
        // on the outer ScrollView ran before the new text had been measured, so the view stayed
        // where it was - and on a log that only ever grows, that means the oldest lines. In
        // practice a Traceback from hours earlier filled the box while the newest, healthy lines
        // sat below the fold, which reads as "the bot is broken".
        //
        // Scrolling the TextView directly, with the target computed from its own layout, is
        // exact, and it keeps touch scrolling and text selection.
        LinearLayout.LayoutParams logParams =
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(260));
        logParams.setMargins(dp(3), dp(3), dp(3), dp(3));
        logView.setLayoutParams(logParams);
        root.addView(logView);

        root.addView(section("工具"));
        root.addView(row(
                action("清除快取", false, false, () -> confirm("清除下載快取與解析記錄？", "/api/cache/clear")),
                action("面板網頁", false, false, this::openInBrowser),
                action("重新整理", false, false, () -> {
                    refreshStatus();
                    loadLog(true);
                })));

        // Its own section, deliberately away from the tools above it.
        //
        // Everything else on this screen is recoverable from this screen: stop the bot and the
        // button beside it starts it again. This is the one control that ends the app's own
        // usefulness, because the panel it talks to is what goes away last. Separating it makes
        // it harder to hit by accident, and the confirmation says plainly what to do afterwards.
        root.addView(section("電源"));
        LinearLayout shutdownRow = new LinearLayout(this);
        shutdownRow.setOrientation(LinearLayout.HORIZONTAL);
        Button shutdown = action("全部關閉（含面板）", false, true, this::confirmShutdown);
        LinearLayout.LayoutParams wide =
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        wide.setMargins(dp(3), dp(3), dp(3), dp(3));
        shutdown.setLayoutParams(wide);
        shutdownRow.addView(shutdown);
        root.addView(shutdownRow);

        TextView note = new TextView(this);
        note.setTextSize(11.5f);
        note.setTextColor(Color.parseColor("#8b93a7"));
        note.setPadding(dp(3), dp(16), dp(3), 0);
        note.setText("這個 app 直接呼叫 Termux 裡既有的腳本：\n"
                + "scripts/start-all.sh、run-bot.sh、run-server.sh。\n\n"
                + "服務沒在跑的時候，上面會出現「一鍵啟動服務」，按下去就好，不需要打開 Termux。\n\n"
                + "按鈕行為與命令列完全一致，所以任何一個都能用指令達成。");
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

    /**
     * Show the card that explains why the app cannot act, and offer the way out.
     *
     * @param title   one line, large
     * @param text    what is wrong, and what will happen if the button is pressed
     * @param action  what the button does; see onBannerButton()
     * @param label   the button's text
     * @param help    monospace text revealed by the second button - the commands to type by hand,
     *                which is the fallback when Termux is not accepting intents
     */
    private void showCard(String title, String text, int action, String label, String help) {
        bannerTitle.setText(title);
        bannerText.setText(text);
        bannerAction = action;
        bannerButton.setText(label);
        if (help == null || help.isEmpty()) {
            bannerDetail.setVisibility(View.GONE);
            bannerDetail.setText("");
        } else {
            // Kept in the view even while hidden: the toggle only flips visibility, so the text
            // is there the moment it is wanted and cannot be lost by a failed refresh.
            bannerDetail.setText(help);
        }
        banner.setVisibility(View.VISIBLE);
    }

    private void hideBanner() {
        banner.setVisibility(View.GONE);
        bannerDetail.setVisibility(View.GONE);
    }

    /** The commands a person would type, for when the automatic path is unavailable. */
    private String manualCommands() {
        return "在 Termux 貼上：\n\n"
                + "bash " + PROJECT_DIR + "/scripts/start-all.sh\n\n"
                + "如果上面那個按鈕按了沒反應，還要先允許外部 app：\n\n"
                + "bash " + PROJECT_DIR + "/scripts/enable-external-apps.sh\n\n"
                + "（執行後要完全關閉 Termux 再重開，它只在啟動時讀設定）";
    }

    private boolean hasRunCommandPermission() {
        // A custom permission from another package; checkSelfPermission handles those the same
        // way as a platform one.
        return checkSelfPermission(PERMISSION_RUN_COMMAND)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
    }

    private void onBannerButton() {
        switch (bannerAction) {
            case ACTION_START:
                startServices();
                break;
            case ACTION_RETRY:
                // A single status poll, so the button feels immediate rather than waiting up to
                // POLL_MS for the loop to come round.
                bannerText.setText("檢查中…");
                refreshStatus();
                break;
            case ACTION_TOGGLE_HELP:
                if (bannerDetail.getVisibility() == View.VISIBLE) {
                    bannerDetail.setVisibility(View.GONE);
                    bannerButton.setText("顯示手動指令");
                } else {
                    bannerDetail.setVisibility(View.VISIBLE);
                    bannerButton.setText("隱藏手動指令");
                }
                break;
            default:
                refreshStatus();
        }
    }

    /**
     * Ask Termux to run start-all.sh.
     *
     * The permission is requested first if it is missing, because the intent would otherwise be
     * dropped without an error of any kind - `startService` on a permission-protected service in
     * another package fails silently from the caller's point of view, and the user would see a
     * button that does nothing.
     */
    private void startServices() {
        android.util.Log.i(TAG, "startServices: permission granted=" + hasRunCommandPermission());
        if (!hasRunCommandPermission()) {
            ui.post(() -> showCard("需要一個權限",
                    "要讓 app 自己啟動服務，需要 Termux 的「執行指令」權限。\n"
                            + "按下面的按鈕授權，然後再按一次啟動。",
                    ACTION_RETRY, "授權後重新檢查", manualCommands()));
            requestPermissions(new String[]{PERMISSION_RUN_COMMAND}, REQ_RUN_COMMAND);
            return;
        }

        Intent intent = new Intent();
        intent.setClassName(TERMUX_PACKAGE, TERMUX_SERVICE);
        intent.setAction(ACTION_RUN_COMMAND);
        intent.putExtra("com.termux.RUN_COMMAND_PATH", TERMUX_BIN + "/bash");
        intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS",
                new String[]{PROJECT_DIR + "/scripts/start-all.sh"});
        intent.putExtra("com.termux.RUN_COMMAND_WORKDIR", PROJECT_DIR);
        // Background, so nothing opens on screen: the point is to start services, not to steal
        // focus with a terminal the user did not ask for.
        intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true);
        intent.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", 0);

        try {
            // **The return value matters.** `startService` returns null when the service was not
            // found or the system declined to start it, and a ComponentName when the request was
            // accepted. It does not throw for either case, so ignoring it - as the first version
            // did - makes "silently did nothing" indistinguishable from "Termux is starting up".
            // The component name is also logged in full so a wrong package or class shows up.
            android.util.Log.i(TAG, "sending RUN_COMMAND to " + TERMUX_PACKAGE + "/" + TERMUX_SERVICE
                    + " args=" + java.util.Arrays.toString(
                            intent.getStringArrayExtra("com.termux.RUN_COMMAND_ARGUMENTS")));
            android.content.ComponentName started = startService(intent);
            android.util.Log.i(TAG, "startService returned " + started);
            if (started == null) {
                showCard("Termux 沒有接受指令",
                        "Android 沒有啟動 Termux 的指令服務。\n\n"
                                + "通常是 Termux 不在執行中，或它的指令服務被系統擋下。"
                                + "請先開啟一次 Termux，再回來按這個按鈕；如果還是不行，用下面的指令。",
                        ACTION_TOGGLE_HELP, "顯示手動指令", manualCommands());
                bannerDetail.setVisibility(View.VISIBLE);
                bannerButton.setText("隱藏手動指令");
                return;
            }
        } catch (Exception exc) {
            // The usual cause is `allow-external-apps` being off, which makes Termux refuse the
            // intent; Android 8+ also refuses startService from the background. Either way the
            // user needs the manual command, not an exception.
            showCard("無法自動啟動",
                    "Termux 拒絕了指令（" + describe(exc) + "）。\n\n"
                            + "最可能的原因是 Termux 還沒允許外部 app 執行指令。請照下面的步驟做一次，"
                            + "之後就可以用按鈕了。",
                    ACTION_TOGGLE_HELP, "顯示手動指令", manualCommands());
            bannerDetail.setVisibility(View.VISIBLE);
            bannerButton.setText("隱藏手動指令");
            return;
        }

        waitingForStart = true;
        showCard("正在啟動服務…",
                "已請 Termux 啟動伺服器、機器人與控制面板。\n"
                        + "順序是伺服器 → 機器人 → 面板，需要幾秒到一分鐘。",
                ACTION_TOGGLE_HELP, "顯示手動指令", manualCommands());
        // Poll harder than the normal interval while waiting, so the card clears as soon as the
        // panel answers rather than up to POLL_MS later.
        ui.postDelayed(this::pollWhileStarting, 2000);
    }

    /**
     * Watch for the services to come up, and give up with an explanation if they do not.
     *
     * The timeout is ~90 s: start-all.sh waits up to 40 s for the server (proot has to build its
     * whole mount table) plus 20 s for the panel.
     */
    private void pollWhileStarting() {
        if (destroyed || !waitingForStart) return;
        refreshStatus();
        startWaitTicks++;
        if (startWaitTicks > 45) {
            startWaitTicks = 0;
            waitingForStart = false;
            showCard("服務沒有回應",
                    "已經等了約 90 秒，控制面板還是沒有回應。\n\n"
                            + "常見原因：Termux 沒有允許外部 app 執行指令，或 Termux 本身被 Android 關掉了。"
                            + "請照下面的步驟手動執行一次。",
                    ACTION_TOGGLE_HELP, "顯示手動指令", manualCommands());
            bannerDetail.setVisibility(View.VISIBLE);
            bannerButton.setText("隱藏手動指令");
            return;
        }
        ui.postDelayed(this::pollWhileStarting, 2000);
    }

    private int startWaitTicks = 0;

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
                    // A successful poll is the detection: whatever the user did - pressed the
                    // button, or ran the command by hand - the card goes away on its own.
                    waitingForStart = false;
                    startWaitTicks = 0;
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
                    // The panel is the only way this app can act, so an unreachable one is the
                    // single failure worth a full card rather than a red dot.
                    if (!waitingForStart) {
                        showCard("服務尚未啟動",
                                "這個 app 透過 Termux 裡的控制面板運作，而面板現在沒有回應（"
                                        + base + "）。\n\n按下面的按鈕讓 app 直接啟動它，"
                                        + "不需要打開 Termux。",
                                ACTION_START, "一鍵啟動服務", manualCommands());
                    }
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
                    //
                    // Posted rather than immediate: the layout must be recomputed for the new
                    // text before the bottom has a position to scroll to, and computing it from
                    // getLayout() is why this survives a long log instead of stopping partway.
                    logView.post(() -> {
                        if (logView.getLayout() == null) return;
                        int content = logView.getLayout().getLineTop(logView.getLineCount());
                        int bottom = Math.max(0, content - logView.getHeight()
                                + logView.getPaddingTop() + logView.getPaddingBottom());
                        logView.scrollTo(0, bottom);
                    });
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

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode != REQ_RUN_COMMAND) return;
        boolean granted = results.length > 0
                && results[0] == android.content.pm.PackageManager.PERMISSION_GRANTED;
        if (granted) {
            startServices();
        } else {
            showCard("權限被拒絕",
                    "沒有這個權限，app 就無法請 Termux 啟動服務。\n\n"
                            + "可以到「設定 → 應用程式 → Bot 控制台 → 權限」手動開啟，"
                            + "或直接用下面的指令。",
                    ACTION_TOGGLE_HELP, "顯示手動指令", manualCommands());
            bannerDetail.setVisibility(View.VISIBLE);
            bannerButton.setText("隱藏手動指令");
        }
    }

    /**
     * Stop the bot, the server and then the panel, and say what happens next.
     *
     * **Not routed through act().** That helper reloads the status and the log when the request
     * returns, and by design the panel is going away at exactly that moment - so the reload would
     * fail and overwrite the confirmation with a connection error, which reads as "the shutdown
     * failed" when it did nothing of the kind. This sends the request, stops polling, and lets
     * the normal status check discover the panel is gone and show the start card on its own.
     */
    private void confirmShutdown() {
        new AlertDialog.Builder(this)
                .setTitle("全部關閉")
                .setMessage("會依序關閉：機器人 → 伺服器 → 控制面板。\n\n"
                        + "面板關掉後，這個 app 就沒有東西可以控制，畫面會變成"
                        + "「服務尚未啟動」。\n\n"
                        + "要重新啟動，按那張卡片的「一鍵啟動服務」就好，不需要打開 Termux。")
                .setPositiveButton("全部關閉", (d, w) -> doShutdown())
                .setNegativeButton("取消", null)
                .show();
    }

    private void doShutdown() {
        // Polling off first: every poll from here on would fail and repaint the screen with an
        // error while the panel is deliberately shutting down.
        waitingForStart = false;
        Toast.makeText(this, "已開始關閉…", Toast.LENGTH_SHORT).show();
        pool.execute(() -> {
            try {
                JSONObject result = request("/api/shutdown", true);
                final boolean ok = result.optBoolean("ok");
                final String note = result.optString("stdout", "").trim();
                ui.post(() -> {
                    if (destroyed) return;
                    Toast.makeText(this,
                            ok ? "已開始關閉，面板會在約 2 秒後停止" : "無法關閉：" + note,
                            ok ? Toast.LENGTH_LONG : Toast.LENGTH_LONG).show();
                    // A last check after the panel has had time to exit, so the start card appears
                    // without waiting for the next scheduled poll.
                    ui.postDelayed(this::refreshStatus, 5000);
                });
            } catch (Exception exc) {
                // Reaching here is normal if the panel exited faster than the reply was read.
                final String message = describe(exc);
                ui.post(() -> {
                    if (destroyed) return;
                    Toast.makeText(this, "面板已停止（" + message + "）", Toast.LENGTH_LONG).show();
                    ui.postDelayed(this::refreshStatus, 3000);
                });
            }
        });
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
