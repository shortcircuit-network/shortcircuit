package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

// DDNSRecord represents one Cloudflare A record
type DDNSRecord struct {
	Name   string `json:"name"`
	Zone   string `json:"zone"`
	Record string `json:"record"`
}

func main() {
	cfToken := os.Getenv("CF_TOKEN")
	if cfToken == "" {
		log.Fatal("CF_TOKEN not set")
	}
	cfEmail := os.Getenv("CF_EMAIL")
	if cfEmail == "" {
		log.Fatal("CF_EMAIL not set")
	}

	recordsJSON := os.Getenv("DDNS_RECORDS_JSON")
	if recordsJSON == "" {
		log.Fatal("DDNS_RECORDS_JSON not set")
	}

	var records []DDNSRecord
	if err := json.Unmarshal([]byte(recordsJSON), &records); err != nil {
		log.Fatalf("invalid DDNS_RECORDS_JSON: %v", err)
	}

	logPath := os.Getenv("LOG_PATH")
	statePath := os.Getenv("STATE_PATH")
	ttl := 120
	if os.Getenv("TTL") != "" {
		fmt.Sscanf(os.Getenv("TTL"), "%d", &ttl)
	}
	log.Printf("Using TTL=%d", ttl)

	if logPath != "" {
		f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			log.Fatal(err)
		}
		defer f.Close()
		log.SetOutput(f)
		log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.Lshortfile)
	}

	currentIP := getPublicIPv4()
	if currentIP == "" {
		log.Fatal("could not obtain public IPv4")
	}

	lastIP := ""
	if statePath != "" {
		if b, err := os.ReadFile(statePath); err == nil {
			lastIP = strings.TrimSpace(string(b))
		}
	}

	if currentIP == lastIP {
		log.Printf("IPv4 unchanged (%s), skipping update", currentIP)
		return
	}

	for _, rec := range records {
		if err := updateCloudflareA(rec, currentIP, cfToken, ttl); err != nil {
			log.Printf("ERROR updating %s: %v", rec.Name, err)
		} else {
			log.Printf("Updated %s -> %s", rec.Name, currentIP)
		}
	}

	if statePath != "" {
		if err := os.WriteFile(statePath, []byte(currentIP), 0644); err != nil {
			log.Printf("ERROR writing state file: %v", err)
		}
	}
}

// getPublicIPv4 fetches the public IPv4 address from redundant providers.
func getPublicIPv4() string {
	providers := []string{"https://api4.ipify.org", "https://4.ifconfig.me"}
	client := &http.Client{Timeout: 5 * time.Second}

	for _, url := range providers {
		for attempt := 0; attempt < 3; attempt++ {
			resp, err := client.Get(url)
			if err != nil {
				time.Sleep(time.Duration(attempt+1) * time.Second)
				log.Printf("Provider %s failed attempt %d: %v", url, attempt+1, err)
				continue
			}
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			ip := strings.TrimSpace(string(body))
			if parsed := net.ParseIP(ip); parsed != nil && parsed.To4() != nil {
				return ip
			}
		}
	}
	return ""
}

// updateCloudflareA updates a Cloudflare A record via the API.
func updateCloudflareA(rec DDNSRecord, ipv4, token string, ttl int) error {
	url := fmt.Sprintf("https://api.cloudflare.com/client/v4/zones/%s/dns_records/%s", rec.Zone, rec.Record)
	payload := map[string]interface{}{
		"type":    "A",
		"name":    rec.Name,
		"content": ipv4,
		"ttl":     ttl,
		"proxied": false,
	}
	body, _ := json.Marshal(payload)
	req, _ := http.NewRequest(http.MethodPut, url, bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	var resp *http.Response
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		resp, err = http.DefaultClient.Do(req)
		if err == nil {
			break
		}
		time.Sleep(time.Duration(attempt+1) * time.Second)
	}
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	var r struct {
		Success bool `json:"success"`
		Errors  []struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		}
	}
	json.NewDecoder(resp.Body).Decode(&r)
	if !r.Success {
		if len(r.Errors) == 0 {
			return fmt.Errorf("Cloudflare API failed: empty response")
		}
		return fmt.Errorf("Cloudflare API failed: %+v", r.Errors)
	}
	return nil
}
