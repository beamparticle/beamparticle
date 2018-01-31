package main

import (
	"flag"
	"fmt"
    "plugin"
    "reflect"
)

var (
    PluginName string
)

func init() {
	flag.StringVar(&PluginName, "plugin_name", "fun_add", "name of the plugin")
}

func main() {
	flag.Parse()

    resp := load_plugin(PluginName)
    fmt.Println("resp is ", resp)

	return
}

func load_plugin(name string) interface{} {
	// load module
	// 1. open the so file to load the symbols
    mod := "golibs/" + name + ".so"
	plug, err := plugin.Open(mod)
	if err != nil {
		fmt.Println(err)
		return nil
	}

	symMain, err := plug.Lookup("Main")
	if err != nil {
		fmt.Println(err)
		return nil
	}

    t := reflect.TypeOf(symMain)
    fmt.Println("t = ", t)

    // https://golang.org/pkg/reflect/#Type
    arity := t.NumIn()
    fmt.Println("Arity is ", arity)
    // t.In(0) is the reflect.Type for first argument
    // t.In(1) is the reflect.Type for second argument
    for i := 0; i < arity; i++ {
        fmt.Printf("Type(%d) = %v\n", i, t.In(i).Kind())
    }
    //fmt.Println("Result = ", t.Method(0).Call(0, 1))
    fmt.Println("NumMethod = ", t.NumMethod())


    v := reflect.ValueOf(symMain)
    fmt.Println("valueof is ", v)
    in := make([]reflect.Value, arity)
    for i := 0; i < arity; i++ {
        in[i] = reflect.ValueOf(i)
    }
    result := v.Call(in)
    fmt.Println("result is", result)
    for i := 0; i < len(result); i++ {
        if result[i] == reflect.ValueOf(nil) {
            fmt.Println("Got nil back as result")
            return nil
        }
        fmt.Printf("result[%d] = %v\n", i, result[i].Kind())
        switch result[i].Kind() {
        case reflect.Struct:
            fmt.Println("struct result = ", result[i].NumField())
        case reflect.Int:
            fmt.Println("int result = ", result[i])
        }
    }

    // t.NumOut() gives the number of output parameters
    // t.Out(0) is the reflect.Type for first output parameter

    /*
	mainfun, ok := symMain.(func())
	if !ok {
		fmt.Println("unexpected type from module symbol")
		return nil
	}

	mainfun()
    */
    return arity
}
