#!/usr/bin/gawk -f

# 12:16:08.099 => millis since epoch
function get_millis(hms, m, orig, hh, mm, ss, ms) {
    orig = hms
    hh = 0; mm = 0; ss = 0; ms = 0
    n = split(hms, xx, "[:.]")
    if (n > 0)
        hh = xx[1]
    if (n > 1)
        mm = xx[2]
    if (n > 2)
        ss = xx[3]
    if (n > 3)
        ms = xx[4]

    m = "2018 1 1 " hh " " mm " " ss
    return mktime(m) + ms
}

function usage() {
    print("Usage:")
    print("  " ARGV[0] " [-v methods=\"meth1,meth2,...\"] [-v sources=\"lco,tau\"] [-v verbs=\"PUT,GET\"] [-v period=\"from,to\"]")
}

BEGIN {
#    if (ARGC == 1 && (ARGV[1] == "-h" || ARGV[1] == "--help")) {
#        usage()
#        exit()
#    fi

    lco_ip = "10.11.0.8:.*"
    tau_ip = "127.0.0.1|132.66.65.9"

    output_mode = "line"
    lco = 0
    tau = 0
    nMethods = 0

    msg = "# sources: "
    if (sources) {
        n = split(sources, s)
        if (n > 0) {
            for (i in s) {
                switch (s[i]) {
                    case "lco":
                        lco = 1
                        break
                    case "tau":
                        tau = 1
                        break
                }
                msg = msg " " s[i]
            }
        }
    } else
        msg = msg " any"
    print(msg)

    msg = "# methods: "
    if (methods) {
        nMethods = split(methods, meths, ",")
        for (i = 1; i <= nMethods; i++) {
            Methods[i-1] = meths[i]
            msg = msg " " meths[i]
        }
    } else
        msg = msg "any"
    print(msg)

    msg = "# verbs:  "
    if (verbs) {
        nVerbs = split(verbs, vrb, ",")
        for (i = 0; i < nVerbs; i++) {
            if (vrb[i] == "GET" || vrb[i] == "PUT") {
                Verbs[i-1] = vrbs[i]
                msg = msg " " vrbs[i]
            } else {
                print("Bad verb \"" vrb[i] "\".  Either GET or PUT")
                usage()
                exit
            }
        }
    } else
        msg = msg "  any"
    print(msg)

    FromTimeMillis = 0
    ToTimeMillis = 0

    msg = "# period:   "
    if (period) {
        # 13:13:21.958, 13:13:21.959
        nTimes = split(period, per, ",")
        if (nTimes > 0) {
            FromTimeMillis = get_millis(per[1])
            # print("FromTimeMillis: " FromTimeMillis)
            msg = msg " from=" per[1]
        }
        if (nTimes > 1) {
            ToTimeMillis = get_millis(per[2])
            # print("ToTimeMillis: " ToTimeMillis)
            msg = msg " to=" per[2]
        }
    } else
        msg = msg "any"
    print(msg)

    if (!lco && !tau) {
        lco = 1
        tau = 1
    }

    if (output_mode == "json")
        print "{"
}

END {
    if (output_mode == "json")
        print "}"
}

{
    sub("\r", "", $0)
    parse($0)
}

function indent(level, s, i, out) {
    for (i = 0; i < level; i++ )
        out = out "  "
    return out s
}

function parse(line, verb, unit, n, tid, url, millis, method, params, driver, pars, p, out, t, words, exception, active, json, v, value, msg) {
    millis = get_millis($1)
    tid = $4

    if ($6 == "GET" || $6 == "PUT") {
        verb = $6
        url = $0
        sub(".*v1/", "", url)
        sub(",.*", "", url)

        split(url, words, "/")
        driver = words[1]
        unit = words[2]
        method = words[3]
        # print "method: ===" method "==="
        sub("?.*", "", method)
        params = words[3]
        sub(".*[?]", "", params)

        transaction[tid, "start_date"] = $1
        #transaction[tid, "start"] = millis
        transaction[tid, "verb"] = verb
        transaction[tid, "url"] = url
        transaction[tid, "driver"] = driver
        transaction[tid, "unit"] = unit
        transaction[tid, "method"] = method
        # transaction[tid, "params"] = params
#        print ""
#        print "transaction: " tid
#        print "  start: " transaction[tid, "start"]
#        print "   verb: " transaction[tid, "verb"]
#        print "    url: " transaction[tid, "url"]
#        print " driver: " transaction[tid, "driver"]
#        print "   unit: " transaction[tid, "unit"]
#        print " method: " transaction[tid, "method"]
#        print " params: " transaction[tid, "params"]

        for (t in active)
            if (transaction[tid, "active"])
                transaction[tid, "active"] = transaction[tid, "active"] " " t
            else
                transaction[tid, "active"] = t
        active[tid] = 1
        #print "transaction[" tid ", driver] = " transaction[tid, "driver"] 
        #print "transaction[" tid ", verb] = " transaction[tid, "verb"] 
    } else if ($7 == "OK") {
        transaction[tid, "result"] = "OK"
        json = line
        sub(".*Json: ", "", json)
        #print "json: " json
        # Escape commas within Json values, otherwise they will split the lines
        if (match(json, "Value\":\"[^\"]*\"", v)) {
            rstart = RSTART
            rlength = RLENGTH
            value = v[0]
            transaction[tid, "value"] = v[0]
            #print "value: ===" value "==="
            gsub(",", "@@@", value)
            #print "value: ---" value "---"
            json = substr(json, 1, rstart - 1) value substr(json, rstart + rlength)
            #gsub("\\", '', json)
            #print "json: " json
        }
        #gsub("\x00\xB0", "Celsius", json)
        gsub(",", ",\n      ", json)
        sub("{", "{\n      ", json)
        sub("}", "\n    }", json)
        gsub("\r", "", json)
        gsub(":", ": ", json)
        gsub("@@@", ",", json)
        transaction[tid, "json"] = json
        # print "OK"
    } else if ($7 == "Exception:") {
        transaction[tid, "result"] = "Ex"
        exception = line
        sub(".*Exception: ", "", exception)
        sub("\r", "", exception)
        msg = substr(line, index(line, "Exception") + length("Exception: "))
        sub("\r", "", msg)
        transaction[tid, "json"] = "{\n  " indent(2, quoted("Exception") ": " quoted(msg)) "\n" indent(2, "}")
        # print "Exception"
    } else if ($7 == "Parameter") {
        if (! ($8 == "ClientID" || $8 == "ClientTransactionID")) {
            if ($10 != "") {
                if (! transaction[tid, "nparams"])
                    transaction[tid, "nparams"] = 0
                n = transaction[tid, "nparams"]
                transaction[tid, "param", n] = $8"="$10
                transaction[tid, "nparams"] = n + 1
            }
        }
    } else if ($7 == "Header" && $8 == "Content-Length") {
        if (transaction[tid, "source"] == "") {
            transaction[tid, "source"] = $5
            #print " source: "  transaction[tid, "source"]
        }
    } else if ($7 == "ProcessRequestAsync" && $0 ~ /Command completed for/) {
        transaction[tid, "source"] = $5
        transaction[tid, "end_date"] = $1
        transaction[tid, "duration"] = get_millis(transaction[tid, "end_date"]) - get_millis(transaction[tid, "start_date"])
        if (output_mode == "json")
            produce_json_transaction_entry(tid, 0)
        else
            produce_line_transaction_entry(tid, 0)
    }
}

function field(label, content, numeric) {
    return indent(2, sprintf("%s: %s,\n", quoted(label), 
           numeric ? content : quoted(content)))
}

function result(label, content, numeric) {
    return indent(2, sprintf("%s: %s\n", quoted(label), 
           numeric ? content : quoted(content)))
}

function param(p, last, word, out, name, value) {
    split(p, word, "=")
    name = word[1]
    value = word[2]
    out = indent(3, quoted("param") ": {\n")
    out = out indent(4, sprintf("%s: %s,\n", quoted("name"), quoted(name)))
    out = out indent(4, sprintf("%s: %s\n", quoted("value"), quoted(value)))
    out = out indent(3, sprintf("}%s\n", last ? "" : ","))
    return out
}

function quoted(s) {
    return "\""s"\""
}

function produce_line_transaction_entry(tid, last, _out, _t, _j) {
    #print("mode: " mode ", source: " transaction[tid, "source"])
    if (!lco && transaction[tid, "source"] ~ lco_ip) {
        return
    }

    if (!tau && transaction[tid, "source"] ~ tau_ip) {
        return
    }

    if (FromTimeMillis && transaction[tid, "start"] < FromTimeMillis)
        return

    if (ToTimeMillis && transaction[tid, "end"] >= ToTimeMillis)
        return

    if (nVerbs) {
        found = 0
        for (i = 0; i < nVerbs; i++) {
            if (Verbs[i] == transaction[tid, "verb"]) {
                found = 1
                break
            }
        }
        if (!found)
            return
    }

    if (nMethods > 0) {
        is_included = 0

        for (i = 0; i < nMethods; i++) {
            # print("included[i]: " included[i] "method: " transaction[tid, "method"])
            if (Methods[i] == transaction[tid, "method"]) {
                is_included = 1
                break
            }
        }

        if (!is_included)
            return
    }

    o = ""
    o = o sprintf("%-25s ",  "source=" transaction[tid, "source"])
    o = o sprintf("%-18s ",  "start=" transaction[tid, "start_date"])
    o = o sprintf("%-18s ",  "end=" transaction[tid, "end_date"])
    # o = o sprintf("%-18s ",  "start_millis=" transaction[tid, "start"])
    # o = o sprintf("%-18s ",  "end_millis=" transaction[tid, "end"])
    o = o sprintf("%-15s ",  "duration=" transaction[tid, "duration"] "ms")
    o = o sprintf("%-10s ",  "tid=" tid)
    o = o sprintf("%-5s " ,  "verb=" transaction[tid, "verb"])
    o = o sprintf("%-20s ",  "driver=" transaction[tid, "driver"])

    m = "method=" transaction[tid, "method"]
    if (transaction[tid, "nparams"]) {
        m = m "("
        for (i = 0; i < transaction[tid, "nparams"]; i++) {
            m = m transaction[tid, "param", i] ", "
        }
        sub(", $", "", m)
        sub(", Parameters=", "", m)
        m = m ")"
    }

    o = o sprintf("%-75s", m)
    o = o "response=" transaction[tid, "result"] " "

    if (transaction[tid, "json"]) {
        _j = transaction[tid, "json"]
        # {"Value":"{
        if (_j ~ /.Value.:.{/) {
            value = _j
            sub(".*.Value.:.", "", value)
            sub(",.*.ClientTransactionID.*", "", value)
            o = o "value=" value
        } else if (_j ~  /.Value.:.[^{]/) {
            value = _j
            sub(".*.Value.:.", "", value)
            sub(",.*ClientTransactionID.*", "", value)
            gsub(/\\/, "", value)
            gsub(/\n/, "", value)
            gsub(/,      /, ", ", value)
            o = o "value=" value
        } else if (transaction[tid, "result"] == "Ex") {
            value = _j
            sub(/.*Exception.:./, "", value)
            sub(/\n[[:space:]]*}/, "", value)
            o = o "value=" value
        }
    }
    print(o)
}

function produce_json_transaction_entry(tid, last, _out, _t) {
        # print "produce_transaction_entry: " tid
        _out = _out indent(1, quoted("server-transaction" "-" tid) ": {\n")
        _out = _out field("id",           tid, 1)
        _out = _out field("verb",         transaction[tid, "verb"], 0)
        _out = _out field("driver",       transaction[tid, "driver"], 0)
        _out = _out field("unit",         transaction[tid, "unit"], 1)
        _out = _out field("method",       transaction[tid, "method"], 0)
        _out = _out field("source",       transaction[tid, "source"], 0)
        if (transaction[tid, "nparams"]) {
            _out = _out indent(2, quoted("params") ": {\n")
            for (n = 0; n < transaction[tid, "nparams"]; n++)
                _out = _out param(transaction[tid, "param", n], 
                    (n+1) == transaction[tid, "nparams"] ? 1 : 0)
            _out = _out indent(2, "},\n")
        }
        _out = _out field("start-millis", transaction[tid, "start"], 1)

        if (transaction[tid, "end"] != "") {
            _out = _out field("end-millis",   transaction[tid, "end"], 1)
            _out = _out field("duration-millis", transaction[tid, "duration"], 1)
        }
        _out = _out field("exception",    transaction[tid, "exception"], 0)

        sub(" $", "", _active)

        #print "before: ==="  transaction[tid, "json"] "==="
        gsub("\\\\", "", transaction[tid, "json"])
        #print "after: ==="  transaction[tid, "json"] "==="
        _out = _out result("result",      transaction[tid, "json"], 1)
        _out = _out indent(1, sprintf("}%s", last ? "" : ",\n"))

        delete transaction[tid]
        print _out
}
