// Command generate writes the test databases for the module tests.
//
// a.mmdb and b.mmdb map the same addresses to different countries. b.mmdb
// also holds many extra networks, so its search tree has another layout. A
// lookup result cached from a.mmdb then points to other data in b.mmdb, which
// makes a stale cache after auto_reload visible.
//
// a.mmdb also maps 192.0.2.0/24 to a record with one value of every MMDB data
// type. v4.mmdb is an IPv4 only database: an IPv6 lookup in it fails.
package main

import (
	"fmt"
	"log"
	"math/big"
	"net"
	"os"
	"path/filepath"

	"github.com/maxmind/mmdbwriter"
	"github.com/maxmind/mmdbwriter/mmdbtype"
)

func country(code string) mmdbtype.Map {
	return mmdbtype.Map{
		"country": mmdbtype.Map{"iso_code": mmdbtype.String(code)},
	}
}

// types holds one value of every MMDB data type.
func types() mmdbtype.Map {
	u128 := new(big.Int).Lsh(big.NewInt(1), 64)
	u128.Add(u128, big.NewInt(2))
	return mmdbtype.Map{
		"types": mmdbtype.Map{
			"bool":   mmdbtype.Bool(true),
			"bytes":  mmdbtype.Bytes("raw"),
			"float":  mmdbtype.Float32(1.5),
			"double": mmdbtype.Float64(-2.25),
			// The longest double nginx prints: its integer part is an int64.
			"double_big": mmdbtype.Float64(-9e18),
			"uint16":     mmdbtype.Uint16(16),
			"uint32":     mmdbtype.Uint32(4000000000),
			"int32":      mmdbtype.Int32(-32),
			"uint64":     mmdbtype.Uint64(18446744073709551615),
			"uint128":    (*mmdbtype.Uint128)(u128),
			"string":     mmdbtype.String("text"),
			// Non-ASCII and reserved characters for escape=uri.
			"escape": mmdbtype.String("Ōbu & Co/ü~"),
			"map":    mmdbtype.Map{"key": mmdbtype.String("value")},
			"array":  mmdbtype.Slice{mmdbtype.String("first")},
		},
	}
}

func insert(w *mmdbwriter.Tree, network string, data mmdbtype.Map) {
	_, ipnet, err := net.ParseCIDR(network)
	if err != nil {
		log.Fatal(err)
	}
	if err := w.Insert(ipnet, data); err != nil {
		log.Fatal(err)
	}
}

func write(path string, ipVersion int, networks [][2]string, extra int, withTypes bool) {
	w, err := mmdbwriter.New(mmdbwriter.Options{
		DatabaseType:            "GeoIP2-Country",
		Description:             map[string]string{"en": "ngx_http_geoip2_module test data"},
		IncludeReservedNetworks: true,
		IPVersion:               ipVersion,
		RecordSize:              28,
	})
	if err != nil {
		log.Fatal(err)
	}
	for _, n := range networks {
		insert(w, n[0], country(n[1]))
	}
	if withTypes {
		insert(w, "192.0.2.0/24", types())
	}
	for i := 0; i < extra; i++ {
		ipnet := &net.IPNet{IP: net.IPv4(10, byte(i>>8), byte(i), 0).To4(), Mask: net.CIDRMask(24, 32)}
		if err := w.Insert(ipnet, country(fmt.Sprintf("X%d", i%10))); err != nil {
			log.Fatal(err)
		}
	}
	f, err := os.Create(path)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	if _, err := w.WriteTo(f); err != nil {
		log.Fatal(err)
	}
}

// Usage: go run . <output directory>
func main() {
	dir := "."
	if len(os.Args) > 1 {
		dir = os.Args[1]
	}
	// Documentation ranges only: RFC 5737 and RFC 3849.
	write(filepath.Join(dir, "a.mmdb"), 6, [][2]string{
		{"203.0.113.0/24", "DE"},
		{"2001:db8::/32", "CH"},
	}, 0, true)
	write(filepath.Join(dir, "b.mmdb"), 6, [][2]string{
		{"203.0.113.0/24", "FR"},
		{"2001:db8::/32", "AT"},
	}, 2000, false)
	write(filepath.Join(dir, "v4.mmdb"), 4, [][2]string{
		{"203.0.113.0/24", "SE"},
	}, 0, false)
}
