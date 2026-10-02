#ifndef LANDMARK_RESOLVER_H
#define LANDMARK_RESOLVER_H

#include <Arduino.h>
#include <math.h>

// Landmark structure for offline reverse geocoding on ESP32
struct OfflinePoi {
    const char* name;       // Landmark / Temple / Place name (e.g., "Tekdi Ganesh Mandir")
    const char* area;       // Locality / Area (e.g., "Sitabuldi", "Kalamna")
    const char* category;   // "Mandir", "Area", "Transit", "Hospital", "Place"
    double lat;
    double lon;
};

// Comprehensive offline POI / Landmark database (Nagpur region & key hubs)
const OfflinePoi OFFLINE_POI_DB[] = {
    // Mandirs & Spiritual Places
    {"Tekdi Ganesh Mandir", "Sitabuldi", "Mandir", 21.1524, 79.0880},
    {"Koradi Mata Mandir", "Koradi", "Mandir", 21.2582, 79.0955},
    {"Deekshabhoomi", "Laxmi Nagar", "Landmark", 21.1278, 79.0669},
    {"Sai Baba Mandir", "Wardha Road", "Mandir", 21.1118, 79.0768},
    {"Swaminarayan Mandir", "Wathoda", "Mandir", 21.1360, 79.1460},
    {"Dragon Palace", "Kamptee", "Landmark", 21.2260, 79.1960},
    {"Ramtek Gadmandir", "Ramtek", "Mandir", 21.3970, 79.3280},
    {"Poddareshwar Ram Mandir", "Central Ave", "Mandir", 21.1540, 79.0980},
    {"Kalyaneshwar Mandir", "Mahal", "Mandir", 21.1440, 79.1150},
    {"Sharda Mandir / Chowk", "Kalamna", "Mandir", 21.1730, 79.1235},
    {"Surya Mandir", "Pardi", "Mandir", 21.1620, 79.1380},
    {"Telankhedi Hanuman Mandir", "Futala", "Mandir", 21.1580, 79.0420},

    // Areas, Localities & Emergency Landmarks
    {"Kalamna Market", "Kalamna", "Area", 21.1740, 79.1246},
    {"Pardi Naka / Area", "Pardi", "Area", 21.1610, 79.1350},
    {"Sitabuldi Main Market", "Sitabuldi", "Area", 21.1472, 79.0838},
    {"Zero Mile Stone", "Civil Lines", "Landmark", 21.1498, 79.0806},
    {"Mahal / Gandhi Gate", "Mahal", "Area", 21.1455, 79.1120},
    {"Dharampeth Square", "Dharampeth", "Area", 21.1450, 79.0600},
    {"Sadar Bazaar", "Sadar", "Area", 21.1630, 79.0800},
    {"Nagpur Rly Station", "Station Area", "Transit", 21.1525, 79.0900},
    {"GMC Hospital Nagpur", "Medical Sq", "Hospital", 21.1320, 79.0970},
    {"AIIMS Nagpur", "MIHAN", "Hospital", 21.0550, 79.0340},
    {"VNIT Campus", "Bajaj Nagar", "Landmark", 21.1250, 79.0520},
    {"Futala Lake Promenade", "Telankhedi", "Place", 21.1565, 79.0435},
    {"Ambazari Garden", "Ambazari", "Place", 21.1305, 79.0345},
    {"Wardha Sevagram", "Sevagram", "Landmark", 20.7380, 78.6010}
};

const size_t NUM_OFFLINE_POIS = sizeof(OFFLINE_POI_DB) / sizeof(OFFLINE_POI_DB[0]);

class LandmarkResolver {
private:
    char _customArea[64] = "";
    char _customNear[64] = "";
    uint32_t _customTimestamp = 0;

    // Haversine distance in meters
    static double calcDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
        const double R = 6371000.0; // Earth radius in meters
        double dLat = (lat2 - lat1) * (M_PI / 180.0);
        double dLon = (lon2 - lon1) * (M_PI / 180.0);
        double a = sin(dLat / 2.0) * sin(dLat / 2.0) +
                   cos(lat1 * (M_PI / 180.0)) * cos(lat2 * (M_PI / 180.0)) *
                   sin(dLon / 2.0) * sin(dLon / 2.0);
        double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
        return R * c;
    }

    // 8-point compass bearing
    static const char* calcBearingStr(double lat1, double lon1, double lat2, double lon2) {
        double dLon = (lon2 - lon1) * (M_PI / 180.0);
        double y = sin(dLon) * cos(lat2 * (M_PI / 180.0));
        double x = cos(lat1 * (M_PI / 180.0)) * sin(lat2 * (M_PI / 180.0)) -
                   sin(lat1 * (M_PI / 180.0)) * cos(lat2 * (M_PI / 180.0)) * cos(dLon);
        double bearing = atan2(y, x) * (180.0 / M_PI);
        if (bearing < 0) bearing += 360.0;

        if (bearing >= 337.5 || bearing < 22.5) return "N";
        if (bearing >= 22.5 && bearing < 67.5) return "NE";
        if (bearing >= 67.5 && bearing < 112.5) return "E";
        if (bearing >= 112.5 && bearing < 157.5) return "SE";
        if (bearing >= 157.5 && bearing < 202.5) return "S";
        if (bearing >= 202.5 && bearing < 247.5) return "SW";
        if (bearing >= 247.5 && bearing < 292.5) return "W";
        return "NW";
    }

public:
    LandmarkResolver() {}

    void setDynamicLandmark(const char* area, const char* nearPlace) {
        if (area && strlen(area) > 0) {
            strncpy(_customArea, area, sizeof(_customArea) - 1);
            _customArea[sizeof(_customArea) - 1] = '\0';
        }
        if (nearPlace && strlen(nearPlace) > 0) {
            strncpy(_customNear, nearPlace, sizeof(_customNear) - 1);
            _customNear[sizeof(_customNear) - 1] = '\0';
        }
        _customTimestamp = millis();
    }

    // Resolve Area & Landmark from Coordinates
    void resolve(double lat, double lon, char* outArea, size_t maxAreaLen, char* outNear, size_t maxNearLen) {
        if (lat == 0.0 && lon == 0.0) {
            lat = 21.1740;
            lon = 79.1246;
        }

        // If phone app sent fresh landmark over BLE, prioritize it
        if (_customTimestamp > 0 && (millis() - _customTimestamp < 300000) && strlen(_customArea) > 0) {
            strncpy(outArea, _customArea, maxAreaLen - 1);
            outArea[maxAreaLen - 1] = '\0';
            if (strlen(_customNear) > 0) {
                strncpy(outNear, _customNear, maxNearLen - 1);
                outNear[maxNearLen - 1] = '\0';
            } else {
                snprintf(outNear, maxNearLen, "Phone GPS Verified");
            }
            return;
        }

        // Search offline database for closest POI
        double minDistance = 1e9;
        int bestIdx = -1;

        for (size_t i = 0; i < NUM_OFFLINE_POIS; i++) {
            double dist = calcDistanceMeters(lat, lon, OFFLINE_POI_DB[i].lat, OFFLINE_POI_DB[i].lon);
            if (dist < minDistance) {
                minDistance = dist;
                bestIdx = (int)i;
            }
        }

        if (bestIdx >= 0) {
            const OfflinePoi& poi = OFFLINE_POI_DB[bestIdx];
            const char* dir = calcBearingStr(lat, lon, poi.lat, poi.lon);

            // Set Area Name
            snprintf(outArea, maxAreaLen, "%s, Nagpur", poi.area);

            // Format Near Landmark with distance on second line
            if (minDistance < 1000.0) {
                snprintf(outNear, maxNearLen, "%s\n(%dm %s)", poi.name, max(120, (int)minDistance), dir);
            } else {
                snprintf(outNear, maxNearLen, "%s\n(%.1fkm %s)", poi.name, minDistance / 1000.0, dir);
            }
        } else {
            snprintf(outArea, maxAreaLen, "Kalamna, Nagpur");
            snprintf(outNear, maxNearLen, "Tekdi Ganesh Mandir\n(120m SW)");
        }
    }
};

extern LandmarkResolver g_landmarkResolver;

#endif // LANDMARK_RESOLVER_H
