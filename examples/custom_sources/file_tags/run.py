from pathlib import Path

from sasram.source import SourceClient


# Each entry contains a source filename, tag name, tag description, and document text.
DOCUMENTS = [
    (
        "password_reset.txt",
        "account-access",
        "Account access and password support.",
        "Password reset guide\n\n"
        "Use the organization's password reset portal to reset a forgotten password. "
        "If you cannot complete identity verification, contact the IT help desk.\n",
    ),
    (
        "vpn_connection.txt",
        "networking",
        "Network connectivity and remote access support.",
        "VPN connection guide\n\n"
        "Connect to the internet, open the approved VPN client, and sign in. "
        "If the connection fails, record the error message for the IT help desk.\n",
    ),
    (
        "laptop_replacement.txt",
        "hardware",
        "Device maintenance and replacement support.",
        "Laptop replacement guide\n\n"
        "Submit a device replacement request through the IT service portal. "
        "Include the asset number and a description of the hardware problem.\n",
    ),
]


def exec(client: SourceClient):
    for filename, tag_name, description, content in DOCUMENTS:
        # Write directly under /tmp so source names do not include random subdirectories.
        path = Path("/tmp") / filename
        path.write_text(content, encoding="utf-8")
        tags = [SourceClient.FileTag(name=tag_name, description=description)]
        # A file can have multiple tags, such as a topic and an intended audience.
        if filename == "password_reset.txt":
            tags.append(SourceClient.FileTag(
                name="employee-onboarding",
                description="Guides relevant to new employees.",
            ))
        # Save and tag separately to avoid the tagged-save duplication seen in RAM.
        client.save_file(str(path))
        # Tag the source filename, not the local /tmp path.
        client.add_tags_to_file(filename, tags)