/*
 *
 * Sample go plugin for dynamic function
 *
 */
package main

import "fmt"

func Main(a int, b int) int {
	fmt.Println("fun_add got ", a, b)
    return a + b
}

