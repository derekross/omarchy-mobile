# SPDX-License-Identifier: MIT

# ftrace and the FWTP text formatter both print timestamps to microseconds.
function micros(s) { return int(s * 1000000 + 0.5) }

FNR == NR {
    if ($0 ~ /^# entries-in-buffer\/entries-written:/ && match($0, /[0-9]+\/[0-9]+/))
        split(substr($0, RSTART, RLENGTH), entries, "/")
    if (!match($0, /[0-9]+\.[0-9]+: /))
        next
    ap = micros(substr($0, RSTART, RLENGTH - 2))
    body = substr($0, RSTART + RLENGTH)
    if (body ~ /^tracing_mark_write: grizzly-cpm-clock (pre|post) (before|after ns=[0-9]+)$/) {
        split(body, marker, " ")
        phase = marker[3]
        if (marker[4] == "before") {
            before[phase] = ap
            starts[phase]++
        } else {
            after[phase] = ap
            gtc[phase] = substr(marker[5], 4) / 1000
            ends[phase]++
        }
    } else if (body ~ /^send_mail_mbfs:[[:space:]]+0x0*220:[^[:space:]]+[[:space:]]+en:1[[:space:]]*$/) {
        request = ap
        requests++
    } else if (body ~ /^recv_result_mbfs:[[:space:]]+0x0*220:[^[:space:]]+[[:space:]]+en:1[[:space:]]+\(res:-?[0-9]+\)[[:space:]]*$/) {
        reply = ap
        replies++
        reply_ok = body ~ /\(res:0\)[[:space:]]*$/
    }
    next
}

{
    target = $0 ~ /(Started p state change|Chg p state).*:[[:space:]]*(524544|0x0*80100)[[:space:]]*$/
    if (!match($0, /^[[:space:]]*([[:alnum:]_.-]+:[[:space:]]+)?[0-9]+\.[0-9]+:[[:space:]]+/)) {
        if (target)
            untimed++
        next
    }
    prefix = substr($0, 1, RLENGTH)
    body = substr($0, RLENGTH + 1)
    match(prefix, /[0-9]+\.[0-9]+/)
    fw = micros(substr(prefix, RSTART, RLENGTH))
    if (!timed || fw < first_fw)
        first_fw = fw
    if (!timed || fw > last_fw)
        last_fw = fw
    timed++
    if (!target)
        next
    if (body !~ /^(Started p state change|Chg p state)/) {
        untimed++
        next
    }
    kind = body ~ /Started p state change/ ? "start" : "complete"
    if (++targets <= 16) {
        printf "psm1-target=0x080100 phase=%s gtc_us=%.0f\n", kind, fw
        target_time[targets] = fw
        target_kind[targets] = kind
    }
    if (kind == "start")
        fw_starts++
    else
        fw_completions++
}

END {
    printf "firmware snapshot timed_lines=%d starts=%d completions=%d untimed_targets=%d omitted=%d\n",
        timed, fw_starts, fw_completions, untimed, (targets > 16 ? targets - 16 : 0)
    if (starts["pre"] != 1 || ends["pre"] != 1 || starts["post"] != 1 ||
        ends["post"] != 1 || gtc["pre"] <= 0 || gtc["post"] <= gtc["pre"] ||
        before["pre"] > after["pre"] || after["pre"] >= before["post"] ||
        before["post"] > after["post"]) {
        print "clock alignment=missing_or_invalid_brackets"
        exit
    }
    pre_lo = before["pre"] - gtc["pre"]
    pre_hi = after["pre"] + 1 - gtc["pre"]
    post_lo = before["post"] - gtc["post"]
    post_hi = after["post"] + 1 - gtc["post"]
    lower = pre_lo > post_lo ? pre_lo : post_lo
    upper = pre_hi < post_hi ? pre_hi : post_hi
    printf "clock brackets pre_us=[%.3f,%.3f] post_us=[%.3f,%.3f]\n", pre_lo, pre_hi, post_lo, post_hi
    if (lower > upper) {
        print "clock alignment=disjoint_brackets"
        exit
    }
    printf "clock alignment=consistent ap_minus_gtc_us=[%.3f,%.3f]\n", lower, upper
    if (entries[1] == "" || entries[1] != entries[2] || requests != 1 ||
        replies != 1 || !reply_ok || request >= reply ||
        after["pre"] > request || before["post"] < reply ||
        untimed || targets > 16) {
        printf "core correlation=incomplete requests=%d replies=%d reply_ok=%d\n", requests, replies, reply_ok
        exit
    }
    if (timed) {
        coverage = first_fw + upper + 1 <= request && last_fw + lower >= reply + 1
        printf "firmware range gtc_us=[%.0f,%.0f] brackets_core=%s\n",
            first_fw, last_fw, (coverage ? "yes" : "no")
    }
    for (i = 1; i <= targets; i++) {
        fw = target_time[i]
        if (fw + upper + 1 < request || fw + lower > reply + 1)
            continue
        if (target_kind[i] == "start") {
            possible_starts++
            start = fw
            start_index = i
        } else {
            possible_completions++
            complete = fw
            complete_index = i
        }
    }
    if (possible_starts != 1 || possible_completions != 1 ||
        start_index >= complete_index || start > complete) {
        if (fw_starts == 1 && fw_completions == 1 &&
            (!possible_starts || !possible_completions))
            print "core correlation=outside"
        else
            printf "core correlation=incomplete possible_starts=%d possible_completions=%d\n",
                possible_starts, possible_completions
        exit
    }
    printf "core window ap_us=[%.0f,%.0f] start_ap_us=[%.3f,%.3f] complete_ap_us=[%.3f,%.3f]\n",
        request, reply, start + lower, start + upper + 1, complete + lower, complete + upper + 1
    if (request + 1 <= start + lower && complete + upper + 1 <= reply)
        print "core correlation=inside"
    else
        print "core correlation=uncertain"
}
