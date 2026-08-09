package app.deterministic.todo.runtracker;

import android.os.Bundle;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.activity.ComponentActivity;

public final class HealthPermissionRationaleActivity extends ComponentActivity {
    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("Privacy movimento");
        int pad = Math.round(24 * getResources().getDisplayMetrics().density);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setPadding(pad, pad, pad, pad);
        TextView text = new TextView(this);
        text.setTextSize(17);
        text.setText("L’app legge da Health Connect soltanto i passi autorizzati per mostrare il totale giornaliero e calcolare stime locali di distanza e calorie attive. I dati restano sul dispositivo: non vengono inviati a Supabase, analytics o servizi pubblicitari. Puoi revocare l’accesso in qualsiasi momento dalle impostazioni di Health Connect.");
        root.addView(text);
        setContentView(root);
    }
}
