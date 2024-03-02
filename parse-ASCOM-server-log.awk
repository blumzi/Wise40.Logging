#!/usr/bin/gawk -f

# 12:16:08.099 => millis since epoch
function get_millis(hms, m) {
    m = hms
    sub(".*[.]", "", m)
    sub("[.].*", "", hms)
    gsub(":", " ", hms)
    return mktime("2018 1 1 "hms) * 1000 + m
}

function usage() {
    print("Usage:")
    print("  " ARGV[0] ":[--lco|--tau] [--line|--json]")
}

BEGIN {
    lco_ip = "10.11.0.8:.*"
    tau_ip = "127.0.0.1|132.66.65.9"

    output_mode = "line"
    mode = "lco"

    if (ARGC > 0) {
        for (a = 1; a < ARGC; a++) {
            switch (ARGV[a]) {
                case "--lco":
                    mode = "lco"
                    delete ARGV[a]
                    break
                case "--tau":
                    mode = "tau"
                    delete ARGV[a]
                    break
                case "--json":
                    output_mode = "json"
                    delete ARGV[a]
                    break
                case "--line":
                    output_mode = "line"
                    delete ARGV[a]
                    break
                default:
                    usage()
                    exit 
                    break
            }
        }
    }

    print "mode: " mode ", output_mode: " output_mode

    if (mode == "json")
        print "{"
}

END {
    if (mode == "json")
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
        transaction[tid, "start"] = millis
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
        transaction[tid, "end_date"] = $1
        transaction[tid, "end"] = millis
        if (transaction[tid, "start"])
            transaction[tid, "duration"] = millis - transaction[tid, "start"]
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
        if (output_mode == "json")
            produce_json_transaction_entry(tid, 0)
        else
            produce_line_transaction_entry(tid, 0)
    } else if ($7 == "Exception:") {
        transaction[tid, "result"] = "Ex"
        transaction[tid, "end_date"] = $1
        transaction[tid, "end"] = millis
        if (transaction[tid, "start"])
            transaction[tid, "duration"] = millis - transaction[tid, "start"]
        exception = line
        sub(".*Exception: ", "", exception)
        sub("\r", "", exception)
        msg = substr(line, index(line, "Exception") + length("Exception: "))
        sub("\r", "", msg)
        transaction[tid, "json"] = "{\n  " indent(2, quoted("Exception") ": " quoted(msg)) "\n" indent(2, "}")
        # print "Exception"
        if (output_mode == "json")
            produce_json_transaction_entry(tid, 0)
        else
            produce_line_transaction_entry(tid, 0)
    } else if ($7 == "Parameter") {
        if (! ($8 == "ClientID" || $10 == "ClientTransactionID")) {
            if (! transaction[tid, "nparams"])
                transaction[tid, "nparams"] = 0
            n = transaction[tid, "nparams"]
            transaction[tid, "param", n] = $8"="$10
            transaction[tid, "nparams"] = n + 1
        }
    } else if ($7 == "ProcessRequestAsync") {
        if (transaction[tid, "source"] == "") {
            transaction[tid, "source"] = $5
            #print " source: "  transaction[tid, "source"]
        }
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
    if (mode == "lco" && transaction[tid, "source"] !~ lco_ip) {
        #print("not lco")
        return
    }

    if (mode == "tau" && transaction[tid, "source"] !~ tau_ip) {
        #print("not tau")
        return
    }

    o = ""
    o = o sprintf("%-15s", "source=" transaction[tid, "source"])
    o = o " [" transaction[tid, "start_date"] ", " transaction[tid, "end_date"] ", " 
    o = o sprintf("%6dms", transaction[tid, "duration"]) "] "
    o = o sprintf("%-10s", "tid=" tid) " verb=" transaction[tid, "verb"] " " sprintf("driver=%-20s", transaction[tid, "driver"])
    o = o sprintf("method=%-30s", transaction[tid, "method"])
    if (transaction[tid, "Action"])
        o = o sprintf("%-25s", "action=" transaction[tid, "Action"])
    else {
        if (transaction[tid, "nparams"]) {
            o = o "params="
            for (i = 0; i < transaction[tid, "nparams"]; i++) {
                o = o transaction[tid, "param", i] ", "
            }
        }
    }

    o = o "response=" transaction[tid, "result"] " "

    if (transaction[tid, "json"]) {
        _j = transaction[tid, "json"]
        # {"Value":"{
        if (_j ~ /.Value.:.{/) {
            value = _j
            sub(".*.Value.:.", "", value)
            sub(",.*.ClientTransactionID.*", "", value)
            o = o "value=" value
        }

        if (_j ~  /.Value.:.[^{]/) {
            value = _j
            sub(".*.Value.:.", "", value)
            sub(",.*ClientTransactionID.*", "", value)
            gsub(/\\/, "", value)
            gsub(/\n/, "", value)
            gsub(/,      /, ", ", value)
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
