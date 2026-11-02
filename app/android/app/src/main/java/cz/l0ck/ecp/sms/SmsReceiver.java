package cz.l0ck.ecp.sms;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Telephony;
import android.telephony.SmsMessage;

import java.util.LinkedHashMap;
import java.util.Map;

/** Incoming SMS: parts joined per sender and handed to [SmsHost]. The SMS stays where the
 *  system put it (default SMS app); ECP only reads what comes from known numbers. */
public class SmsReceiver extends BroadcastReceiver {

	@Override
	public void onReceive(Context context, Intent intent) {
		if (!Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) return;
		Map<String, StringBuilder> bySender = new LinkedHashMap<>();
		for (SmsMessage m : Telephony.Sms.Intents.getMessagesFromIntent(intent)) {
			if (m == null || m.getOriginatingAddress() == null) continue;
			bySender.computeIfAbsent(m.getOriginatingAddress(), k -> new StringBuilder())
					.append(m.getMessageBody());
		}
		SmsHost host = SmsHost.get(context);
		for (Map.Entry<String, StringBuilder> e : bySender.entrySet()) {
			host.deliver(e.getKey(), e.getValue().toString());
		}
	}
}
