# Privacy Policy

**Bram's Bounding App**
Last updated: April 8, 2026

## Overview

Bram's Bounding App ("the App") is designed with privacy in mind. All data is stored locally on your device. The only external communication occurs when you choose to analyze an image using the Claude AI service.

## Data Collection

**We do not collect, store, or transmit any personal data.** The App does not have a backend server, user accounts, or analytics.

## Data Storage

All data is stored locally on your device using Apple's SwiftData framework:

- **Photos**: Images you capture or select are stored on-device only.
- **Bounding Boxes**: Extracted text and coordinates are stored on-device only.
- **API Key**: Your Claude API key is stored on-device using Apple's AppStorage. It is never transmitted to any server other than Anthropic's API.
- **Embeddings**: Semantic similarity vectors are computed and cached on-device using Apple's NLEmbedding framework.

## Third-Party Services

### Anthropic (Claude AI)

When you choose to analyze a photo, the image is sent to Anthropic's Claude API for processing. This is the **only** external network request the App makes. Anthropic's use of this data is governed by their own privacy policy and API terms of service:

- [Anthropic Privacy Policy](https://www.anthropic.com/privacy)
- [Anthropic API Terms](https://www.anthropic.com/api-terms)

**You provide your own API key.** The App does not use a shared or developer-owned key. You are responsible for your own Anthropic account and usage.

No image data is stored on Anthropic's servers beyond what is necessary to process the API request, per Anthropic's API data retention policy.

## Camera and Photo Library Access

The App requests access to your device's camera and photo library solely to capture or select images for analysis. These permissions are required for core functionality and are not used for any other purpose.

## Data Sharing

The App does **not**:

- Share data with third parties (other than Anthropic API calls you initiate)
- Include advertising or ad tracking
- Use analytics or crash reporting services
- Transmit data to any server owned or operated by the developer

## Data Deletion

All data can be deleted at any time by:

- Deleting individual photos within the App
- Deleting the App from your device, which removes all associated data

## Children's Privacy

The App does not knowingly collect information from children under 13. The App has no user accounts or data collection mechanisms.

## Changes to This Policy

If this privacy policy is updated, the changes will be reflected in this document with an updated date.

## Contact

If you have questions about this privacy policy, please open an issue at:
https://github.com/bramses/Brams-Bounding-App/issues
