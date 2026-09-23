// Command generate writes the test databases for the module tests.
//
// a.mmdb and b.mmdb map the same addresses to different countries. b.mmdb
// also holds many extra networks, so its search tree has another layout. A
// lookup result cached from a.mmdb then points to other data in b.mmdb, which
// makes a stale cache after auto_reload visible.
package main

import (
	"fmt"
	"log"
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

func write(path string, networks [][2]string, extra int) {
	w, err := mmdbwriter.New(mmdbwriter.Options{
		DatabaseType:            "GeoIP2-Country",
		Description:             map[string]string{"en": "ngx_http_geoip2_module test data"},
		IncludeReservedNetworks: true,
		RecordSize:              28,
	})
	if err != nil {
		log.Fatal(err)
	}
	for _, n := range networks {
		_, ipnet, err := net.ParseCIDR(n[0])
		if err != nil {
			log.Fatal(err)
		}
		if err := w.Insert(ipnet, country(n[1])); err != nil {
			log.Fatal(err)
		}
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
	write(filepath.Join(dir, "a.mmdb"), [][2]string{
		{"203.0.113.0/24", "DE"},
		{"2001:db8::/32", "CH"},
	}, 0)
	write(filepath.Join(dir, "b.mmdb"), [][2]string{
		{"203.0.113.0/24", "FR"},
		{"2001:db8::/32", "AT"},
	}, 2000)
}
