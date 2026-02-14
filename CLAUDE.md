# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains the solution for the **Pollinate Platform Engineering Technical Assessment**. The assessment involves designing and implementing a healthcare integration platform.

## Assessment Requirements

The technical assessment is documented in `documentation/Pollinate Platform Engineering Technical Assessment.docx.pdf`. Key areas include:

- **Healthcare System Integration**: Building interfaces for healthcare data exchange
- **Event-Driven Architecture**: Implementing asynchronous message processing
- **Patient Data Processing**: Handling patient records with proper data transformation
- **HIPAA Compliance**: Ensuring security and privacy controls for PHI (Protected Health Information)
- **API Design**: RESTful API design for healthcare endpoints

## Architecture Principles

When implementing solutions in this repository:

1. **Security First**: All code handling patient data must follow HIPAA compliance requirements
2. **Event-Driven Patterns**: Use message queues/event streams for decoupled system communication
3. **Observability**: Include logging, tracing, and monitoring in all components
4. **API Versioning**: Support backward-compatible API evolution
5. **Infrastructure as Code**: Use IaC tools (Terraform/CloudFormation) for all infrastructure

## Development Notes

- Reference the PDF in `documentation/` for complete assessment requirements and evaluation criteria
- All implementations should be production-ready with appropriate error handling
