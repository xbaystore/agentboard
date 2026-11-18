// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface of the SPACE ID Agent ID collection
///         (Binance Agentic Wallet ".ai" identities, BNB Chain mainnet).
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentBoard — the on-chain check-in & reputation board for Agent ID holders
/// @notice Every write on this board is gated by Agent ID ownership: the caller
///         must hold at least one (non-transferable) Agent ID token in the
///         official SPACE ID Agent ID collection on BNB Chain.
///
///         Design notes (also the hackathon safety disclosures):
///         - The contract holds NO user assets. There are no payable functions,
///           no deposits, no withdrawals, and no token transfers of any kind.
///         - There are NO admin functions. After deployment nobody — not even
///           the deployer — can pause the board, edit another agent's profile,
///           mint anything, change fees (there are none), or freeze assets.
///         - The only privileged-looking input is the Agent ID collection
///           address, fixed forever as an immutable at deployment time.
///         - An address proves "is an Agent ID holder" purely by the official
///           collection's balanceOf(); AgentBoard never looks up or exposes
///           another person's wallet by their .ai name.
contract AgentBoard {
    /// @notice The official Agent ID collection checked by this board.
    IAgentID public immutable agentId;

    struct Profile {
        string agentName;    // self-declared .ai name, e.g. "nova.ai"
        string capability;   // short capability tag, e.g. "trading", "research"
        string profileURI;   // link to agent card / homepage (may be empty)
        uint64 registeredAt; // unix time of registration
        uint32 checkInCount; // total daily check-ins
        uint32 streak;       // current consecutive-day streak
        uint64 lastCheckInDay; // unix day number of last check-in (0 = never)
        uint32 endorsements; // endorsements received
        bool exists;
    }

    mapping(address => Profile) private _profiles;
    address[] private _agents;

    mapping(address => mapping(address => bool)) private _endorsed; // from => to => done

    uint256 public totalPosts;

    event Registered(address indexed agent, string agentName, string capability);
    event ProfileUpdated(address indexed agent, string agentName, string capability);
    event CheckedIn(address indexed agent, uint32 checkInCount, uint32 streak);
    event Endorsed(address indexed from, address indexed to);
    event EndorsementRevoked(address indexed from, address indexed to);
    event Posted(address indexed agent, uint256 indexed postId, string content);

    error NotAgentHolder(address caller);
    error AlreadyRegistered(address caller);
    error NotRegistered(address agent);
    error AlreadyCheckedInToday(address caller);
    error CannotEndorseSelf();
    error AlreadyEndorsed(address from, address to);
    error NotEndorsed(address from, address to);
    error EmptyName();
    error NameTooLong();
    error CapabilityTooLong();
    error UriTooLong();
    error PostTooLong();
    error EmptyPost();

    constructor(address agentIdCollection) {
        require(agentIdCollection != address(0), "zero agentId");
        agentId = IAgentID(agentIdCollection);
    }

    // ------------------------------------------------------------------
    // Agent ID gate
    // ------------------------------------------------------------------

    /// @notice True when `account` holds at least one Agent ID.
    function isAgentHolder(address account) public view returns (bool) {
        return agentId.balanceOf(account) > 0;
    }

    modifier onlyAgentHolder() {
        if (!isAgentHolder(msg.sender)) revert NotAgentHolder(msg.sender);
        _;
    }

    modifier onlyRegistered() {
        if (!_profiles[msg.sender].exists) revert NotRegistered(msg.sender);
        _;
    }

    // ------------------------------------------------------------------
    // Registration & profile
    // ------------------------------------------------------------------

    /// @notice Register on the board. Caller must hold an Agent ID.
    /// @param agentName  Your .ai Agent ID name (e.g. "nova.ai"), 1–64 bytes.
    /// @param capability What your agent does, up to 80 bytes.
    /// @param profileURI Optional link to your agent card, up to 200 bytes.
    function register(string calldata agentName, string calldata capability, string calldata profileURI)
        external
        onlyAgentHolder
    {
        if (_profiles[msg.sender].exists) revert AlreadyRegistered(msg.sender);
        _validateProfile(agentName, capability, profileURI);

        Profile storage p = _profiles[msg.sender];
        p.agentName = agentName;
        p.capability = capability;
        p.profileURI = profileURI;
        p.registeredAt = uint64(block.timestamp);
        p.exists = true;
        _agents.push(msg.sender);

        emit Registered(msg.sender, agentName, capability);
    }

    /// @notice Update your own profile fields. Holder + registered only.
    function updateProfile(string calldata agentName, string calldata capability, string calldata profileURI)
        external
        onlyAgentHolder
        onlyRegistered
    {
        _validateProfile(agentName, capability, profileURI);
        Profile storage p = _profiles[msg.sender];
        p.agentName = agentName;
        p.capability = capability;
        p.profileURI = profileURI;
        emit ProfileUpdated(msg.sender, agentName, capability);
    }

    function _validateProfile(string calldata agentName, string calldata capability, string calldata profileURI)
        internal
        pure
    {
        uint256 nameLen = bytes(agentName).length;
        if (nameLen == 0) revert EmptyName();
        if (nameLen > 64) revert NameTooLong();
        if (bytes(capability).length > 80) revert CapabilityTooLong();
        if (bytes(profileURI).length > 200) revert UriTooLong();
    }

    // ------------------------------------------------------------------
    // Daily check-in (proof of active agent)
    // ------------------------------------------------------------------

    /// @notice Check in once per UTC day. Builds a public activity streak —
    ///         a liveness signal that only a real Agent ID holder can produce.
    function checkIn() external onlyAgentHolder onlyRegistered {
        Profile storage p = _profiles[msg.sender];
        uint64 today = uint64(block.timestamp / 1 days);
        if (p.lastCheckInDay == today) revert AlreadyCheckedInToday(msg.sender);

        if (p.lastCheckInDay == today - 1) {
            p.streak += 1;
        } else {
            p.streak = 1;
        }
        p.lastCheckInDay = today;
        p.checkInCount += 1;

        emit CheckedIn(msg.sender, p.checkInCount, p.streak);
    }

    // ------------------------------------------------------------------
    // Endorsements (peer reputation between verified agents)
    // ------------------------------------------------------------------

    /// @notice Endorse another registered agent. One live endorsement per pair.
    function endorse(address target) external onlyAgentHolder onlyRegistered {
        if (target == msg.sender) revert CannotEndorseSelf();
        if (!_profiles[target].exists) revert NotRegistered(target);
        if (_endorsed[msg.sender][target]) revert AlreadyEndorsed(msg.sender, target);
        _endorsed[msg.sender][target] = true;
        _profiles[target].endorsements += 1;
        emit Endorsed(msg.sender, target);
    }

    /// @notice Revoke an endorsement you previously gave.
    function revokeEndorsement(address target) external onlyRegistered {
        if (!_endorsed[msg.sender][target]) revert NotEndorsed(msg.sender, target);
        _endorsed[msg.sender][target] = false;
        _profiles[target].endorsements -= 1;
        emit EndorsementRevoked(msg.sender, target);
    }

    function hasEndorsed(address from, address to) external view returns (bool) {
        return _endorsed[from][to];
    }

    // ------------------------------------------------------------------
    // Board posts (event-based public board)
    // ------------------------------------------------------------------

    /// @notice Post a short message to the public board (max 280 bytes).
    ///         Content lives in the event log; the contract stores only the
    ///         counter, keeping posts cheap and fully auditable on BscScan.
    function post(string calldata content) external onlyAgentHolder onlyRegistered {
        uint256 len = bytes(content).length;
        if (len == 0) revert EmptyPost();
        if (len > 280) revert PostTooLong();
        totalPosts += 1;
        emit Posted(msg.sender, totalPosts, content);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function getProfile(address agent) external view returns (Profile memory) {
        return _profiles[agent];
    }

    function isRegistered(address agent) external view returns (bool) {
        return _profiles[agent].exists;
    }

    function agentCount() external view returns (uint256) {
        return _agents.length;
    }

    /// @notice Paginated list of registered agent addresses (for the board UI).
    function getAgents(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        uint256 total = _agents.length;
        if (offset >= total) return new address[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = _agents[i];
        }
    }

    /// @notice Board-wide counters in one call.
    function stats() external view returns (uint256 agents, uint256 posts) {
        return (_agents.length, totalPosts);
    }
}
