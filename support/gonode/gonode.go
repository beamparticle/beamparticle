/*
 *
 * IMPORATANT: Storing dynamic functions as go plugins increases both
 *             the storage requirements (since .so consumes sufficient disk)
 *             and consumed open file descriptor since the go application
 *             (which is this application) need to open the plugin before
 *             executing it.
 *
 *
 * Based on ergonode/examples/gonode.go
 * see https://github.com/halturin/ergonode/blob/master/examples/gonode.go
 */

package main

import (
	"flag"
	"fmt"
	"github.com/halturin/ergonode"
	"github.com/halturin/ergonode/etf"
    "io/ioutil"
    "os"
    "plugin"
    "reflect"
    "os/exec"
)

// GenServer implementation structure
type goGenServ struct {
	ergonode.GenServer
	completeChan chan bool
}

var (
	SrvName   string
	NodeName  string
	Cookie    string
	err       error
	EpmdPort  int
	EnableRPC bool
    ErlangNodeName string
    PluginSrc string
    PluginPath string
)

// Init initializes process state using arbitrary arguments
func (gs *goGenServ) Init(args ...interface{}) interface{} {
	// Self-registration with name go_srv
	gs.Node.Register(etf.Atom(SrvName), gs.Self)

	// Store first argument as channel
	gs.completeChan = args[0].(chan bool)

	return nil
}

// HandleCast serves incoming messages sending via gen_server:cast
func (gs *goGenServ) HandleCast(message *etf.Term, state interface{}) (code int, stateout interface{}) {
	fmt.Printf("HandleCast: %#v", *message)
	stateout = state
	code = 0
	// Check type of message
	switch req := (*message).(type) {
	case etf.Tuple:
		if len(req) == 2 {
			switch act := req[0].(type) {
			case etf.Atom:
				if string(act) == "ping" {
					var self_pid etf.Pid = gs.Self
					rep := etf.Term(etf.Tuple{etf.Atom("pong"), etf.Pid(self_pid)})
					gs.Send(req[1].(etf.Pid), &rep)

				}
			}
		}
	case etf.Atom:
		// If message is atom 'stop', we should say it to main process
		if string(req) == "stop" {
			gs.completeChan <- true
		}
	}
	return
}

// HandleCall serves incoming messages sending via gen_server:call
func (gs *goGenServ) HandleCall(from *etf.Tuple, message *etf.Term, state interface{}) (code int, reply *etf.Term, stateout interface{}) {
	// fmt.Printf("HandleCall: %#v, From: %#v\n", *message, *from)

	defer func() {
		if r := recover(); r != nil {
			fmt.Printf("Call recovered: %#v\n", r)
		}
	}()

	stateout = state
	code = 1
	replyTerm := etf.Term(etf.Tuple{etf.Atom("error"), etf.Atom("unknown_request")})
	reply = &replyTerm

	switch req := (*message).(type) {
	case etf.Atom:
		// If message is atom 'stop', we should say it to main process
		switch string(req) {
		case "pid":
			replyTerm = etf.Term(etf.Pid(gs.Self))
			reply = &replyTerm
		}
	case etf.Tuple:
		var cto, cmess etf.Term
		// {testcall, { {name, node}, message  }}
		// {testcast, { {name, node}, message  }}
		if len(req) == 3 {
			// moduleName := req[0].(etf.Atom)
			functionName := req[1].(etf.Atom)
            arguments := req[2].(etf.List)

			if string(functionName) == "invoke" {
                nameBinary := arguments[0].(string)
                codeBinary := arguments[1].(string)
                name := string(nameBinary)
                code := string(codeBinary)
                plug := load_plugin(name)
                if plug == nil {
                    loadReply := try_load_dynamic_function(name, code)
                    if loadReply.(etf.Tuple)[0] == etf.Atom("ok") {
                        plug = load_plugin(name)
                        if plug == nil {
                            replyTerm = etf.Term(etf.Tuple{etf.Atom("error"),
                                                           etf.Atom("strange_error")})
                        } // TODO else
                    }
                } // TODO else
            } else if string(functionName) == "invoke_simple_http" {
                // TODO FIXME
                replyTerm = etf.Term(etf.Tuple{etf.Atom("error"),
                                               etf.Atom("not_supported")})
            } else if string(functionName) == "eval" {
                replyTerm = etf.Term(etf.Tuple{etf.Atom("error"),
                                               etf.Atom("not_supported")})
            } else if string(functionName) == "load" {
				fmt.Printf("Load %#v\n", arguments)
                if len(arguments) != 2 {
                    fmt.Printf("Bad arguments to load %#v\n", arguments)
                } else {
                    nameBinary := arguments[0].(string)
                    codeBinary := arguments[1].(string)
                    name := string(nameBinary)
                    code := string(codeBinary)
                    replyTerm = try_load_dynamic_function(name, code)
                }
			} else if string(functionName) == "testcast" {
				fmt.Println("testcast...")
				gs.Cast(cto, &cmess)
				fmt.Println("testcast...2222")
				replyTerm = etf.Term(etf.Atom("ok"))
				reply = &replyTerm
				fmt.Println("testcast...3333")
			} else {
				return
			}

		}
	}
	return
}

// HandleInfo serves all another incoming messages (Pid ! message)
func (gs *goGenServ) HandleInfo(message *etf.Term, state interface{}) (code int, stateout interface{}) {
	fmt.Printf("HandleInfo: %#v\n", *message)
	stateout = state
	code = 0
	return
}

// Terminate called when process died
func (gs *goGenServ) Terminate(reason int, state interface{}) {
	fmt.Printf("Terminate: %#v\n", reason)
}

func init() {
	flag.StringVar(&SrvName, "gen_server", "golangserver", "gen_server name")
	flag.StringVar(&NodeName, "name", "go@127.0.0.1", "node name")
	flag.StringVar(&Cookie, "cookie", "123", "cookie for interaction with erlang cluster")
	flag.IntVar(&EpmdPort, "epmd_port", 15151, "epmd port")
	flag.BoolVar(&EnableRPC, "rpc", false, "enable RPC")
	flag.StringVar(&ErlangNodeName, "erlang_name", "beamparticle@127.0.0.1", "Erlang node name")
	flag.StringVar(&PluginSrc, "plugin_src", "golangsrc", "Go plugin source folder name")
	flag.StringVar(&PluginPath, "plugin_path", "golanglibs", "Go plugin compiled shared object folder name")
}

func main() {
	flag.Parse()

	// Initialize new node with given name and cookie
	n := ergonode.Create(NodeName, uint16(EpmdPort), Cookie)

	// Create channel to receive message when main process should be stopped
	completeChan := make(chan bool)

	// Initialize new instance of goGenServ structure which implements Process behaviour
	gs := new(goGenServ)

	// Spawn process with one arguments
	n.Spawn(gs, completeChan)

	// RPC
	// Create closure
	rpc := func(terms etf.List) (r etf.Term) {
		r = etf.Term(etf.Tuple{etf.Atom(NodeName), etf.Atom("reply"), len(terms)})
		return
	}

	// Provide it to call via RPC with `rpc:call(gonode@localhost, rpc, call, [as, qwe])`
	err = n.RpcProvide("rpc", "call", rpc)
	if err != nil {
		fmt.Printf("Cannot provide function to RPC: %s\n", err)
	}

	fmt.Println("Allowed commands...")
	fmt.Printf("gen_server:cast({%s,'%s'}, stop).\n", SrvName, NodeName)
	fmt.Printf("gen_server:call({%s,'%s'}, pid).\n", SrvName, NodeName)
	fmt.Printf("gen_server:cast({%s,'%s'}, {ping, self()}), flush().\n", SrvName, NodeName)
	fmt.Println("make remote call by golang node...")
	fmt.Printf("gen_server:call({%s,'%s'}, {testcall, {Pid, Message}}).\n", SrvName, NodeName)
	fmt.Printf("gen_server:call({%s,'%s'}, {testcall, {{pname, remotenode}, Message}}).\n", SrvName, NodeName)

	// Wait to stop
	<-completeChan

	return
}

func save_plugin(name string, code string) int {
    filename := "golangsrc/" + name + ".go"
    codebyte := []byte(code)
    err := ioutil.WriteFile(filename, codebyte, 0644)
    if err != nil {
        return -1
    }
    return 0
}

func compile_plugin(name string) int {
    soName := "golanglibs/" + name + ".so"
    srcName := "golangsrc/" + name + ".go"
    cmd := exec.Command("go", "build", "-buildmode=plugin", "-o", soName, srcName)
    currentDir, err := os.Getwd()
    if err != nil {
        return -1
    }
    cmd.Env = append(os.Environ(),
        "GOPATH=" + currentDir + "/go",
    )
    if err := cmd.Run(); err != nil {
        fmt.Println(err)
        return -1
    }
    return 0
}

func load_plugin(name string) *plugin.Plugin {
    // read plugin from so file
    mod := "golanglibs/" + name + ".so"
	plug, err := plugin.Open(mod)
	if err != nil {
		fmt.Println(err)
		return nil
	}

    return plug
}

func method_arity(plug *plugin.Plugin, name string) int {
    symMethod, err := plug.Lookup(name)
    if err != nil {
        fmt.Println(err)
        return -1
    }

    t := reflect.TypeOf(symMethod)
    arity := t.NumIn()
    return arity
}

func run_plugin_method(
    plug *plugin.Plugin, name string, args []reflect.Value) interface{} {
    symMethod, err := plug.Lookup(name)
    if err != nil {
        fmt.Println(err)
        return nil
    }

    t := reflect.TypeOf(symMethod)
    arity := t.NumIn()
    if arity != len(args) {
        fmt.Printf("Method arity do not match %v != %v\n", arity, len(args))
        return nil
    }
    v := reflect.ValueOf(symMethod)
    result := v.Call(args)
    return result
}

func try_load_dynamic_function(name string, code string) etf.Term {
    switch save_plugin(name, code) {
    case 0:
        // IMPORTANT: do not allow same name with different arity
        //            for now. This is largely due to the fact that
        //            arity of a function is not detectable without
        //            loading it. But, once the plugin is loaded
        //            there is no support (at present) to unload the
        //            plugin in golang.
        switch compile_plugin(name) {
        case 0:
            plug := load_plugin(name)
            if plug == nil {
                return etf.Term(etf.Tuple{etf.Atom("error"),
                                          etf.Atom("load_failure")})
            } else {
                arity := method_arity(plug, "Main")
                if arity == -1 {
                    return etf.Term(etf.Tuple{etf.Atom("error"),
                                              etf.Atom("no_main")})
                } else {
                    return etf.Term(etf.Tuple{etf.Atom("ok"), arity})
                }
            }
        default:
            return etf.Term(etf.Tuple{etf.Atom("error"),
                                      etf.Atom("compile_failure")})
        }
    default:
        return etf.Term(etf.Tuple{etf.Atom("error"),
                                  etf.Atom("save_failure")})
    }
	return etf.Term(etf.Tuple{etf.Atom("error"),
                              etf.Atom("unknown_request")})
}


