# Security Policy

## Supported Versions

We release patches for security vulnerabilities. Which versions are eligible depends on the CVSS v3.0 Rating:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability within this project, please follow these steps:

1. **Do NOT** create a public GitHub issue
2. Send details to the maintainers through GitHub Security Advisories
3. Include the following in your report:
   - Description of the vulnerability
   - Steps to reproduce
   - Possible impact
   - Suggested fix (if any)

### What to expect

- Acknowledgment of your report within 48 hours
- Regular updates on our progress
- Credit for responsible disclosure (unless you prefer to remain anonymous)

## Security Best Practices

When using this gem:

1. **API Key Management**
   - Never commit API keys to version control
   - Use Rails credentials or environment variables
   - Rotate API keys regularly
   - Use different keys for different environments

2. **Rails Security**
   - Keep Rails and dependencies updated
   - Follow Rails security best practices
   - Use strong parameters
   - Implement proper authentication and authorization

3. **Data Handling**
   - Be cautious with sensitive data in logs
   - Use Rails encrypted credentials
   - Implement proper error handling
   - Sanitize user input before syncing to Attio

## Security Features

This gem includes:
- Integration with Rails security features
- Automatic API key masking in logs
- SSL/TLS verification by default
- Input validation and sanitization
- Safe handling of ActiveRecord callbacks

## Contact

For security concerns, please use GitHub Security Advisories or contact the maintainers directly through GitHub.