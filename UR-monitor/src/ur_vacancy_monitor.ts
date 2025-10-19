#!/usr/bin/env node
/**
 * UR Vacancy Monitor Script
 * Monitors UR-NET vacancy API every minute and sends Slack notifications when rooms are available.
 */

import axios, { AxiosResponse } from 'axios';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL;
const UR_API_URL = "https://chintai.r6.ur-net.go.jp/chintai/api/bukken/search/map_marker/";
const STATE_FILE = "vacancy_state.json";

if (!SLACK_WEBHOOK_URL) {
    throw new Error("SLACK_WEBHOOK_URL environment variable is required");
}

// Types
interface Property {
    id: string;
    roomCount: number;
}

interface PropertyState {
    roomCount: number;
    alarmCount: number;
    lastUpdated: string;
}

interface VacancyState {
    properties: Record<string, PropertyState>; // property_id -> PropertyState
    lastCheck: string | null;
}

interface SlackMessage {
    msg: string;
}

// Set up logging
const log = {
    info: (message: string) => {
        const timestamp = new Date().toISOString();
        console.log(`${timestamp} - INFO - ${message}`);
    },
    error: (message: string) => {
        const timestamp = new Date().toISOString();
        console.error(`${timestamp} - ERROR - ${message}`);
    },
    warning: (message: string) => {
        const timestamp = new Date().toISOString();
        console.warn(`${timestamp} - WARNING - ${message}`);
    }
};

async function getUrVacancies(): Promise<Property[] | null> {
    const headers = {
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7,ja;q=0.6',
        'Connection': 'keep-alive',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'DNT': '1',
        'Origin': 'https://www.ur-net.go.jp',
        'Referer': 'https://www.ur-net.go.jp/',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-site',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
        'sec-ch-ua': '"Google Chrome";v="141", "Not?A_Brand";v="8", "Chromium";v="141"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"macOS"'
    };

    const data = new URLSearchParams({
        'rent_low': '',
        'rent_high': '',
        'floorspace_low': '',
        'floorspace_high': '',
        'ne_lat': '35.60315369606699',
        'ne_lng': '139.8051626955953',
        'sw_lat': '35.43661044565526',
        'sw_lng': '139.4632132327046',
        'small': 'false'
    });

    try {
        const response: AxiosResponse<Property[]> = await axios.post(UR_API_URL, data, {
            headers,
            timeout: 30000
        });
        return response.data;
    } catch (error) {
        if (axios.isAxiosError(error)) {
            log.error(`Error fetching UR data: ${error.message}`);
        } else {
            log.error(`Unexpected error fetching UR data: ${error}`);
        }
        return null;
    }
}

function loadState(): VacancyState {
    try {
        if (fs.existsSync(STATE_FILE)) {
            const data = fs.readFileSync(STATE_FILE, 'utf8');
            const rawState = JSON.parse(data);

            // Handle backward compatibility with old state format
            if (rawState.previousProperties && rawState.alarmCounts) {
                // Convert old format to new format
                const properties: Record<string, PropertyState> = {};
                const currentTime = new Date().toISOString();

                for (const [propId, roomCount] of Object.entries(rawState.previousProperties as Record<string, number>)) {
                    properties[propId] = {
                        roomCount,
                        alarmCount: rawState.alarmCounts[propId] || 0,
                        lastUpdated: currentTime
                    };
                }

                return {
                    properties,
                    lastCheck: rawState.lastCheck
                };
            }

            // Return new format if already converted
            return rawState as VacancyState;
        }
    } catch (error) {
        log.error(`Error loading state: ${error}`);
    }

    // Return default state if file doesn't exist or is corrupted
    return {
        properties: {},
        lastCheck: null
    };
}

function saveState(state: VacancyState): void {
    try {
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    } catch (error) {
        log.error(`Error saving state: ${error}`);
    }
}

async function sendSlackNotification(messageText: string): Promise<boolean> {
    const message: SlackMessage = {
        msg: messageText
    };

    // Print message for debugging
    console.log("=== DEBUG: Slack Message ===");
    console.log(JSON.stringify(message, null, 2));
    console.log("============================");

    try {
        await axios.post(SLACK_WEBHOOK_URL!, message, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 10000
        });
        log.info("Slack notification sent successfully");
        return true;
    } catch (error) {
        if (axios.isAxiosError(error)) {
            log.error(`Error sending Slack notification: ${error.message}`);
        } else {
            log.error(`Unexpected error sending Slack notification: ${error}`);
        }
        return false;
    }
}

function processVacancyChanges(currentProperties: Record<string, number>, state: VacancyState): string[] {
    const { properties } = state;
    const notifications: string[] = [];
    const currentTime = new Date().toISOString();

    // Check for newly added properties or increased room counts
    for (const [propId, roomCount] of Object.entries(currentProperties)) {
        const existingProperty = properties[propId];

        if (!existingProperty) {
            // Completely new property - reset alarm count and send notification
            const newProperty: PropertyState = {
                roomCount,
                alarmCount: 1,
                lastUpdated: currentTime
            };
            properties[propId] = newProperty;
            notifications.push(`🆕 NEW Property ${propId}: ${roomCount} rooms available - https://www.ur-net.go.jp/chintai/kanto/kanagawa/${propId}.html`);
        } else if (roomCount > existingProperty.roomCount) {
            // Existing property with more rooms - reset alarm count because there's a change
            const previousRoomCount = existingProperty.roomCount;
            existingProperty.alarmCount = 1; // Reset to 1 (this is the first notification for this change)
            existingProperty.roomCount = roomCount;
            existingProperty.lastUpdated = currentTime;
            notifications.push(`📈 INCREASED Property ${propId}: ${roomCount} rooms available (was ${previousRoomCount}) - https://www.ur-net.go.jp/chintai/kanto/kanagawa/${propId}.html`);
        } else if (roomCount === existingProperty.roomCount) {
            // No change in room count - check if we should send repeated notification
            if (existingProperty.alarmCount < 3) {
                existingProperty.alarmCount += 1;
                existingProperty.lastUpdated = currentTime;
                notifications.push(`🔄 REMINDER Property ${propId}: ${roomCount} rooms still available - https://www.ur-net.go.jp/chintai/kanto/kanagawa/${propId}.html`);
            } else {
                // Just update timestamp, no notification (already sent 3 alarms)
                existingProperty.lastUpdated = currentTime;
            }
        }
    }

    // Check for disappeared properties or decreased room counts
    for (const [propId, propertyState] of Object.entries(properties)) {
        if (!(propId in currentProperties)) {
            // Property completely disappeared
            notifications.push(`❌ DISAPPEARED Property ${propId}: No longer available (had ${propertyState.roomCount} rooms)`);
            // Remove property from state when it disappears
            delete properties[propId];
        } else if (currentProperties[propId] < propertyState.roomCount) {
            // Existing property with fewer rooms - reset alarm count because there's a change
            const previousRoomCount = propertyState.roomCount;
            propertyState.alarmCount = 1; // Reset to 1 (this is the first notification for this change)
            propertyState.roomCount = currentProperties[propId];
            propertyState.lastUpdated = currentTime;
            notifications.push(`📉 DECREASED Property ${propId}: ${currentProperties[propId]} rooms available (was ${previousRoomCount}) - https://www.ur-net.go.jp/chintai/kanto/kanagawa/${propId}.html`);
        }
    }

    return notifications;
}

async function sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function monitorVacancies(): Promise<void> {
    log.info("Starting UR vacancy monitoring...");

    // Load previous state
    const state = loadState();

    while (true) {
        try {
            log.info("Checking for vacancies...");
            const vacancies = await getUrVacancies();

            if (vacancies === null) {
                log.warning("Failed to fetch vacancy data, retrying in 1 minute...");
                await sleep(60000);
                continue;
            }

            // Convert to dict of property_id -> roomCount for easier comparison
            const currentProperties: Record<string, number> = {};
            for (const prop of vacancies) {
                if (prop.roomCount > 0) {
                    currentProperties[prop.id] = prop.roomCount;
                }
            }

            // Process changes and get notifications
            const notifications = processVacancyChanges(currentProperties, state);

            // Send notifications if any
            if (notifications.length > 0) {
                const timestamp = new Date().toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' });
                const totalRooms = Object.values(currentProperties).reduce((sum, count) => sum + count, 0);
                const header = `🏠 UR Vacancy Update at ${timestamp} - ${Object.keys(currentProperties).length} properties with ${totalRooms} total rooms`;

                const messageText = header + "\n\n" + notifications.join("\n");
                await sendSlackNotification(messageText);
            } else {
                const totalRooms = Object.values(currentProperties).reduce((sum, count) => sum + count, 0);
                log.info(`No changes detected. Current: ${Object.keys(currentProperties).length} properties with ${totalRooms} total rooms`);
            }

            // Update state
            state.lastCheck = new Date().toISOString();
            saveState(state);

            // Wait for 1 minute before next check
            log.info("Waiting 60 seconds before next check...");
            await sleep(60000);

        } catch (error) {
            if (error instanceof Error && error.message === 'SIGINT') {
                log.info("Monitoring stopped by user");
                break;
            }
            log.error(`Unexpected error: ${error}`);
            log.info("Continuing monitoring after error...");
            await sleep(60000);
        }
    }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
    log.info("Received SIGINT, shutting down gracefully...");
    process.exit(0);
});

process.on('SIGTERM', () => {
    log.info("Received SIGTERM, shutting down gracefully...");
    process.exit(0);
});

// Start monitoring if this file is run directly
if (require.main === module) {
    monitorVacancies().catch((error) => {
        log.error(`Fatal error: ${error}`);
        process.exit(1);
    });
}
