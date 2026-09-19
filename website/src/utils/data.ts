export const links = {
    github: "https://github.com/golobitch/tb-explorer",
    releases: "https://github.com/golobitch/tb-explorer/releases",
    download: "https://github.com/golobitch/tb-explorer/releases/latest",
    readme: "https://github.com/golobitch/tb-explorer#readme",
    issues: "https://github.com/golobitch/tb-explorer/issues",
    tigerbeetle: "https://tigerbeetle.com",
};

export const downloadAsset = "TigerBeetle-Explorer-macos-universal.zip";

export const navItems = [
    { href: "#features", text: "Features" },
    { href: "#read-only", text: "Read-only" },
    { href: "#install", text: "Install" },
    { href: "#compatibility", text: "Compatibility" },
    { href: "#open-source", text: "Open source" },
];

export const aptRepository = "https://golobitch.github.io/tb-explorer/apt";

export type Install = {
    title: string;
    subtitle: string;
    description: string;
    command: string;
    alternative: string;
    alternativeHref: string;
};

// The one command each front end is installed with. Everything longer — the apt keyring and
// .sources file — lives in the READMEs rather than on a landing page.
export const installs: Install[] = [
    {
        title: "The macOS app",
        subtitle: "Homebrew cask · macOS 15+",
        description:
            "A notarized universal build, so it opens without a detour through System Settings.",
        command: "brew install --cask golobitch/tap/tb-explorer",
        alternative: "Or download the zip and check it against SHA256SUMS",
        alternativeHref: links.download,
    },
    {
        title: "The terminal UI",
        subtitle: "Homebrew formula · macOS and Linux",
        description:
            "tb-tui browses the same data with k9s-style navigation, on the machine the cluster runs on.",
        command: "brew install golobitch/tap/tb-tui",
        alternative: "On Debian and Ubuntu, install it from the apt repository instead",
        alternativeHref: "https://github.com/golobitch/tb-explorer/tree/main/cli#install",
    },
];

const svg = (paths: string) =>
    `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6" aria-hidden="true">${paths}</svg>`;

export type Feature = {
    title: string;
    description: string;
    icon: string;
};

export const features: Feature[] = [
    {
        title: "Saved connections",
        description:
            "Keep a list of clusters with name, cluster id, replica addresses and when you last used them. The overview shows the cluster id, client version, a live latency check and the ledgers discovered so far.",
        icon: svg(`<path stroke-linecap="round" stroke-linejoin="round" d="M5.25 14.25h13.5m-13.5 0a3 3 0 01-3-3m3 3a3 3 0 100 6h13.5a3 3 0 100-6m-16.5-3a3 3 0 013-3h13.5a3 3 0 013 3m-19.5 0a4.5 4.5 0 01.9-2.7L5.737 5.1a3.375 3.375 0 012.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 01.9 2.7m0 0a3 3 0 01-3 3m0 3h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008zm-3 6h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008z" />`),
    },
    {
        title: "Accounts & transfers, cluster-wide",
        description:
            "Browse accounts and transfers with server-side filters for ledger, code and user_data. Results page by timestamp cursor and load more as you scroll.",
        icon: svg(`<path stroke-linecap="round" stroke-linejoin="round" d="M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5" />`),
    },
    {
        title: "Account detail",
        description:
            "Every field and decoded flag, the account's transfers filtered to debits and/or credits, find a transfer by id, and a Raw tab where every field is copyable.",
        icon: svg(`<path stroke-linecap="round" stroke-linejoin="round" d="M15 9h3.75M15 12h3.75M15 15h3.75M4.5 19.5h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5zm6-10.125a1.875 1.875 0 11-3.75 0 1.875 1.875 0 013.75 0zm1.294 6.336a6.721 6.721 0 01-3.17.789 6.721 6.721 0 01-3.168-.789 3.376 3.376 0 016.338 0z" />`),
    },
    {
        title: "Balance history",
        description:
            "A Swift Charts step chart of get_account_balances with exact values on hover, plus a table. Double-click a row to open the transfer that produced it.",
        icon: svg(`<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 18L9 11.25l4.306 4.307a11.95 11.95 0 015.814-5.519l2.74-1.22m0 0l-5.94-2.28m5.94 2.28l-2.28 5.941" />`),
    },
    {
        title: "Pending → post / void chains",
        description:
            "See whether a pending transfer was posted, voided, expired or is still pending. Search Wider extends the lookback tenfold. Linked transfers show every member of their group.",
        icon: svg(`<path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244" />`),
    },
    {
        title: "Search & ⌘K Go to ID",
        description:
            "Paste an id and the app detects account vs transfer, or query by ledger, code, user_data and time range. Copy ids as decimal or hex. Light and dark mode follow the system.",
        icon: svg(`<path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />`),
    },
];
