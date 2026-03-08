# Design Review: API Redesign

An AI drafted this proposal. Read through it, accept or reject the suggestions, leave your feedback, and advance the status when you're done.

## Status

<!-- status: draft | under review | approved | shipped -->
**Status:** draft

Click the status above to move it forward through the pipeline.

## Proposed Changes

The AI has marked up its suggestions inline. Green means addition, red means deletion, strikethrough means substitution. Hover over each one and click Accept or Reject.

### Authentication

The auth layer should {++migrate to OAuth 2.0 with PKCE++} for all client applications.

We currently {--use API key authentication, which--} expose{~~s~>d~~} credentials in request headers.

### Rate Limiting

{==No rate limiting exists on the public endpoints.==}{>>This is a security risk — recommend 100 req/min per client.<<}

All public endpoints should {++enforce rate limiting at 100 requests per minute++} with exponential backoff on 429 responses.

### Data Format

Response payloads will {~~use XML~>return JSON~~} with consistent envelope structure.

The {--legacy v1 endpoints will be maintained for 6 months before--} deprecat{~~ion~>ed endpoints will redirect to v2~~}.

## Architecture Decision

> **Proceed with this redesign?**
> - [ ] Yes, as proposed
> - [ ] Yes, with modifications
> - [ ] No, needs rethinking

## Your Feedback

Anything the AI should know? Click below to leave a note:

<!-- feedback -->

## What You Just Did

You reviewed a document like a real design review — accepting and rejecting inline changes, advancing a status through its pipeline, making a decision, and leaving feedback. All saved to the file.

Next up: **04-Release-Checklist** — a QA scenario that brings everything together.
