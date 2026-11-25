// account/uptime-alert/index.mjs - Turns the uptime alarm into a short email, sent through neon1-notify: a subject
// that says what happened, one line, and a link to the site.

import { CloudWatchClient, DescribeAlarmHistoryCommand } from "@aws-sdk/client-cloudwatch";
import { InvokeCommand, LambdaClient } from "@aws-sdk/client-lambda";

const SITE = "https://neon1.tech/";
const cloudwatch = new CloudWatchClient({});
const lambda = new LambdaClient({});


// Eastern time, the way the rest of neon1 writes it
const clock = (at) => `${new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" }).format(at)} Eastern`;


// When the outage now ending began: the newest change into ALARM, or nothing if the history doesn't show one
async function wentDown(name) {
  const { AlarmHistoryItems = [] } = await cloudwatch.send(new DescribeAlarmHistoryCommand({ AlarmName: name, HistoryItemType: "StateUpdate", ScanBy: "TimestampDescending", MaxRecords: 20 }));
  return AlarmHistoryItems.find((i) => /to ALARM/.test(i.HistorySummary))?.Timestamp;
}


// The same light card as neon1's other mail, holding only the line and the link
const page = (line) => `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"></head>
<body style="margin:0;padding:20px 10px;font:16px/1.55 Figtree,-apple-system,'Segoe UI',Roboto,sans-serif">
<p style="margin:0 0 12px">${line}</p><p style="margin:0"><a href="${SITE}">neon1.tech</a></p></body></html>`;


// The notice for one alarm change, or nothing when there's no news (such as the first reading after setup)
export function message(change, since) {
  const at = new Date(change.StateChangeTime);
  if (change.NewStateValue === "ALARM") {
    return { severity: "important", key: "uptime-down", subject: "neon1.tech is down", line: `The home page stopped passing its outside check at ${clock(at)}.` };
  }
  if (change.NewStateValue !== "OK" || change.OldStateValue !== "ALARM") return undefined;
  const minutes = since ? Math.max(1, Math.round((at - since) / 60000)) : undefined;
  return { severity: "info", key: "uptime-up", subject: `neon1.tech is back up${minutes ? ` (down ${minutes} min)` : ""}`, line: `The home page passed its check again at ${clock(at)}.` };
}


export async function handler(event) {
  for (const record of event.Records) {
    const change = JSON.parse(record.Sns.Message);
    const since = change.NewStateValue === "OK" ? await wentDown(change.AlarmName) : undefined;
    const mail = message(change, since);
    if (!mail) continue;
    const notice = {
      severity: mail.severity, title: mail.subject, text: mail.line, url: SITE, source: "uptime", dedupeKey: mail.key,
      email: { subject: mail.subject, text: `${mail.line}\n${SITE}`, html: page(mail.line), to: process.env.RECIPIENTS.split(",") },
    };
    const out = await lambda.send(new InvokeCommand({ FunctionName: process.env.NOTIFY_FUNCTION, Payload: Buffer.from(JSON.stringify(notice)) }));
    // A failed send throws, so SNS tries again
    const result = JSON.parse(Buffer.from(out.Payload ?? []).toString() || "{}");
    if (out.FunctionError || result.delivered?.email === "error") throw new Error("neon1-notify did not send the email");
    console.log(JSON.stringify({ event: "uptime_notice", state: change.NewStateValue, delivered: result.delivered }));
  }
}
