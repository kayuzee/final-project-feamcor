pragma solidity 0.5.2;

import "./Ownable.sol";
import "./Counter.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";


/// @author Fábio Corrêa <feamcor@gmail.com>
/// @title Bileto: a simple decentralized ticket store on Ethereum
/// @notice Final project for ConsenSys Academy's Developer Bootcamp 2019.
contract Bileto is Ownable, ReentrancyGuard {
    enum StoreStatus {
        Created,   // 0
        Open,      // 1
        Suspended, // 2
        Closed     // 3
    }

    enum EventStatus {
        Created,        // 0
        SalesStarted,   // 1
        SalesSuspended, // 2
        SalesFinished,  // 3
        Completed,      // 4
        Settled,        // 5
        Cancelled       // 6
    }

    enum PurchaseStatus {
        Completed, // 0
        Cancelled, // 1
        Refunded,  // 2
        CheckedIn  // 3
    }

    struct Store {
        StoreStatus status;
        string name;
        uint refundable;
        Counter.Counter_ counterEvents;
        Counter.Counter_ counterPurchases;
    }

    struct Event {
        EventStatus status;
        bytes32 externalId;
        address payable organizer;
        string name;
        uint storeIncentive;
        uint ticketPrice;
        uint ticketsOnSale;
        uint ticketsSold;
        uint ticketsLeft;
        uint ticketsCancelled;
        uint ticketsRefunded;
        uint ticketsCheckedIn;
        uint eventBalance;
        uint refundableBalance;
    }

    struct Purchase {
        PurchaseStatus status;
        bytes32 externalId;
        uint timestamp;
        address payable customer;
        bytes32 customerId;
        uint quantity;
        uint total;
        uint eventId;
    }

    Store private store;

    mapping(uint => Event) private events;

    mapping(uint => Purchase) private purchases;

    mapping(address => uint[]) private organizerEvents;

    mapping(address => uint[]) private customerPurchases;

    /// @notice Ticket store was opened.
    /// @param _by store owner address (indexed)
    /// @dev corresponds to `StoreStatus.Open`
    event StoreOpen(address indexed _by);

    /// @notice Ticket store was suspended.
    /// @param _by store owner address (indexed)
    /// @dev corresponds to `StoreStatus.Suspended`
    event StoreSuspended(address indexed _by);

    /// @notice Ticket store was closed.
    /// @param _by store owner address (indexed)
    /// @dev corresponds to `StoreStatus.Closed`
    event StoreClosed(address indexed _by);

    /// @notice Ticket event was created.
    /// @param _id event new internal ID (indexed) 
    /// @param _extId hash of the event external ID (indexed)
    /// @param _by store owner address (indexed)
    /// @dev corresponds to `EventStatus.Created`
    event EventCreated(uint indexed _id, bytes32 indexed _extId, address indexed _by);

    /// @notice Event ticket sales was started.
    /// @param _id event internal ID (indexed) 
    /// @param _extId hash of the event external ID (indexed)
    /// @param _by events organizer address (indexed)
    /// @dev corresponds to `EventStatus.SalesStarted`
    event EventSalesStarted(uint indexed _id, bytes32 indexed _extId, address indexed _by);

    /// @notice Event ticket sales was suspended.
    /// @param _id event internal ID (indexed) 
    /// @param _extId hash of the event external ID (indexed)
    /// @param _by events organizer address (indexed)
    /// @dev corresponds to `EventStatus.SalesSuspended`
    event EventSalesSuspended(uint indexed _id, bytes32 indexed _extId, address indexed _by);

    /// @notice Event ticket sales was finished.
    /// @param _id event internal ID (indexed) 
    /// @param _extId hash of the event external ID (indexed)
    /// @param _by events organizer address (indexed)
    /// @dev corresponds to `EventStatus.SalesFinished`
    event EventSalesFinished(uint indexed _id, bytes32 indexed _extId, address indexed _by);

    /// @notice Ticket event was completed.
    /// @param _id event new internal ID (indexed) 
    /// @param _extId hash of the event external ID (indexed)
    /// @param _by events organizer address (indexed)
    /// @dev corresponds to `EventStatus.Completed`
    event EventCompleted(uint indexed _id, bytes32 indexed _extId, address indexed _by);

    /// @notice Ticket event was settled.
    /// @param _id event internal ID (indexed) 
    /// @param _extId hash of the event external ID (indexed)
    /// @param _by store owner address (indexed)
    /// @param _settlement amount settled (transferred) to event organizer
    /// @dev corresponds to `EventStatus.Settled`
    event EventSettled(uint indexed _id, bytes32 indexed _extId, address indexed _by, uint _settlement);

    /// @notice Ticket event was cancelled.
    /// @param _id event internal ID (indexed) 
    /// @param _extId hash of the event external ID (indexed)
    /// @param _by event organizer address (indexed)
    /// @dev corresponds to `EventStatus.Cancelled`
    event EventCancelled(uint indexed _id, bytes32 indexed _extId, address indexed _by);

    /// @notice Ticket purchase was completed.
    /// @param _id purchase new internal ID (indexed) 
    /// @param _extId hash of the purchase external ID (indexed)
    /// @param _by customer address (indexed)
    /// @param _id event internal ID 
    /// @dev corresponds to `PurchaseStatus.Completed`
    event PurchaseCompleted(uint indexed _id, bytes32 indexed _extId, address indexed _by, uint _eventId);

    /// @notice Ticket purchase was cancelled.
    /// @param _id purchase internal ID (indexed) 
    /// @param _extId hash of the purchase external ID (indexed)
    /// @param _by customer address (indexed)
    /// @param _id event internal ID 
    /// @dev corresponds to `PurchaseStatus.Cancelled`
    event PurchaseCancelled(uint indexed _id, bytes32 indexed _extId, address indexed _by, uint _eventId);

    /// @notice Ticket purchase was refunded.
    /// @param _id purchase internal ID (indexed) 
    /// @param _extId hash of the purchase external ID (indexed)
    /// @param _by customer address (indexed)
    /// @param _id event internal ID 
    /// @dev corresponds to `PurchaseStatus.Refunded`
    event PurchaseRefunded(uint indexed _id, bytes32 indexed _extId, address indexed _by, uint _eventId);

    /// @notice Customer checked in the event.
    /// @param _eventId event internal ID (indexed)
    /// @param _purchaseId purchase internal ID (indexed) 
    /// @param _by customer address (indexed)
    /// @dev corresponds to `PurchaseStatus.CheckedIn`
    event CustomerCheckedIn(uint indexed _eventId, uint indexed _purchaseId, address indexed _by);

    /// @dev Verify that ticket store is open, otherwise revert.
    modifier storeOpen() {
        require(store.status == StoreStatus.Open,
            "ticket store must be open in order to proceed");
        _;
    }

    /// @dev Verify that event ID is within current range.
    modifier validEventId(uint _eventId) {
        require(_eventId <= store.counterEvents.current,
            "invalid event ID");
        _;
    }

    /// @dev Verify that purchase ID is within current range.
    modifier validPurchaseId(uint _purchaseId) {
        require(_purchaseId <= store.counterPurchases.current,
            "invalid purchase ID");
        _;
    }

    /// @dev Verify that transaction on an event was triggered by its organizer, otherwise revert.
    modifier onlyOrganizer(uint _eventId) {
        require(msg.sender == events[_eventId].organizer,
            "must be triggered by event organizer in order to proceed");
        _;
    }

    /// @dev Verify that transaction on an event was triggered by its organizer or store owner.
    modifier onlyOwnerOrOrganizer(uint _eventId) {
        require(isOwner() || msg.sender == events[_eventId].organizer,
            "must be triggered by event organizer or store owner in order to proceed");
        _;
    }

    /// @dev Verify that a purchase was completed, otherwise revert.
    modifier purchaseCompleted(uint _purchaseId) {
        require(purchases[_purchaseId].status == PurchaseStatus.Completed,
            "ticket purchase have to be completed in order to proceed");
        _;
    }

    /// @notice Initialize the ticket store and its respective owner.
    /// @dev store owner is set by the account who created the store
    constructor(string memory _name) public {
        require(bytes(_name).length != 0,
            "store name must not be empty in order to proceed");
        store.name = _name;
        store.status = StoreStatus.Created;
    }

    /// @notice Fallback function.
    function()
        external
        payable
    {
        require(msg.data.length == 0,
            "only funds transfer (i.e. no data) accepted on fallback");
    }

    /// @notice Open ticket store.
    /// @dev emit `StoreOpen` event
    function openStore()
        external
        nonReentrant
        onlyOwner
    {
        require(store.status == StoreStatus.Created
            || store.status == StoreStatus.Suspended,
            "ticket store must be created or suspended in order to proceed");
        store.status = StoreStatus.Open;
        emit StoreOpen(msg.sender);
    }

    /// @notice Suspend ticket store.
    /// @notice Should be used with extreme caution and on exceptional cases only.
    /// @dev emit `StoreSuspended` event
    function suspendStore()
        external
        nonReentrant
        onlyOwner
        storeOpen
    {
        store.status = StoreStatus.Suspended;
        emit StoreSuspended(msg.sender);
    }

    /// @notice Close ticket store.
    /// @notice This is ticket store final state and become inoperable after.
    /// @notice Ticket store won't close while there are refundable balance left.
    /// @dev emit `StoreClosed` event
    function closeStore()
        external
        nonReentrant
        onlyOwner
    {
        require(store.status != StoreStatus.Closed,
            "ticket store cannot be closed in order to proceed");
        require(store.refundable == 0,
            "ticket store refundable balance must be zero in order to proceed");
        store.status = StoreStatus.Closed;
        emit StoreClosed(msg.sender);
    }

    /// @notice Create a ticket event.
    /// @param _externalId event external ID provided by organizer. Will be stored hashed
    /// @param _organizer event organizer address. Will be able to manage the event thereafter
    /// @param _name event name
    /// @param _storeIncentive commission granted to store upon sale of tickets. From 0.00% (000) to 100.00% (10000)
    /// @param _ticketPrice ticket price (in wei)
    /// @param _ticketsOnSale number of tickets available for sale
    /// @return Event internal ID.
    /// @dev emit `EventCreated` event
    function createEvent(
        string calldata _externalId,
        address payable _organizer,
        string calldata _name,
        uint _storeIncentive,
        uint _ticketPrice,
        uint _ticketsOnSale
    )
        external
        nonReentrant
        onlyOwner
        storeOpen
        returns (uint _eventId)
    {
        require(!Address.isContract(_organizer),
            "organizer address must refer to an account (i.e. not a contract) in order to proceed");
        require(bytes(_externalId).length != 0,
            "ticket event external ID must not be empty in order to proceed");
        require(bytes(_name).length != 0,
            "ticket event name must not be empty in order to proceed");
        require(_storeIncentive >= 0
            && _storeIncentive <= 10000,
            "store incentive must be between 0.00% (000) to 100.00% (10000) in order to proceed");
        require(_ticketsOnSale > 0,
            "number of tickets available for sale cannot be zero in order to proceed");
        _eventId = Counter.next(store.counterEvents);
        events[_eventId].status = EventStatus.Created;
        events[_eventId].externalId = keccak256(bytes(_externalId));
        events[_eventId].organizer = _organizer;
        events[_eventId].name = _name;
        events[_eventId].storeIncentive = _storeIncentive;
        events[_eventId].ticketPrice = _ticketPrice;
        events[_eventId].ticketsOnSale = _ticketsOnSale;
        events[_eventId].ticketsLeft = _ticketsOnSale;
        organizerEvents[_organizer].push(_eventId);
        emit EventCreated(_eventId, events[_eventId].externalId, msg.sender);
        return (_eventId);
    }

    /// @notice Start sale of tickets for an event.
    /// @param _eventId event internal ID
    /// @dev emit `EventSalesStarted` event
    function startTicketSales(uint _eventId)
        external
        nonReentrant
        storeOpen
        validEventId(_eventId)
        onlyOrganizer(_eventId)
    {
        require(events[_eventId].status == EventStatus.Created
            || events[_eventId].status == EventStatus.SalesSuspended,
            "ticket event must be created or with sales suspended in order to proceed");
        events[_eventId].status = EventStatus.SalesStarted;
        emit EventSalesStarted(_eventId, events[_eventId].externalId, msg.sender);
    }

    /// @notice Suspend sale of tickets for an event.
    /// @param _eventId event internal ID
    /// @dev emit `EventSalesSuspended` event
    function suspendTicketSales(uint _eventId)
        external
        nonReentrant
        storeOpen
        validEventId(_eventId)
        onlyOrganizer(_eventId)
    {
        require(events[_eventId].status == EventStatus.SalesStarted,
            "event ticket sales must have started in order to proceed");
        events[_eventId].status = EventStatus.SalesSuspended;
        emit EventSalesSuspended(_eventId, events[_eventId].externalId, msg.sender);
    }

    /// @notice End sale of tickets for an event.
    /// @notice It means that no tickets for the event can be sold thereafter.
    /// @param _eventId event internal ID
    /// @dev emit `EventSalesFinished` event
    function endTicketSales(uint _eventId)
        external
        nonReentrant
        storeOpen
        validEventId(_eventId)
        onlyOrganizer(_eventId)
    {
        require(events[_eventId].status == EventStatus.SalesStarted
            || events[_eventId].status == EventStatus.SalesSuspended,
            "event ticket sales must have started or be suspended in order to proceed");
        events[_eventId].status = EventStatus.SalesFinished;
        emit EventSalesFinished(_eventId, events[_eventId].externalId, msg.sender);
    }

    /// @notice Complete an event.
    /// @notice It means that the event is past and can be settled (paid out to organizer).
    /// @param _eventId event internal ID
    /// @dev emit `EventCompleted` event
    function completeEvent(uint _eventId)
        external
        nonReentrant
        storeOpen
        validEventId(_eventId)
        onlyOrganizer(_eventId)
    {
        require(events[_eventId].status == EventStatus.SalesFinished, 
            "event ticket sales must have finished in order to proceed");
        events[_eventId].status = EventStatus.Completed;
        emit EventCompleted(_eventId, events[_eventId].externalId, msg.sender);
    }

    /// @notice Settle an event.
    /// @notice It means that (non-refundable) funds will be transferred to organizer.
    /// @notice No transfer will be performed if settlement balance is zero,
    /// @notice even though event will be considered settled.
    /// @param _eventId event internal ID
    /// @dev emit `EventSettled` event
    function settleEvent(uint _eventId)
        external
        nonReentrant
        storeOpen
        onlyOwner
    {
        require(events[_eventId].status == EventStatus.Completed,
            "ticket event must have been completed in order to proceed");
        events[_eventId].status = EventStatus.Settled;
        uint _eventBalance = events[_eventId].eventBalance;
        uint _storeIncentive = events[_eventId].storeIncentive;
        uint _storeBalance = SafeMath.div(SafeMath.mul(_eventBalance, _storeIncentive), 10000);
        uint _settlement = SafeMath.sub(_eventBalance, _storeBalance);
        if (_settlement > 0) {
            events[_eventId].organizer.transfer(_settlement);
        }
        emit EventSettled(_eventId, events[_eventId].externalId, msg.sender, _settlement);
    }

    /// @notice Cancel an event.
    /// @notice It means that ticket sales will stop and sold tickets (purchases) are refundable.
    /// @param _eventId event internal ID
    /// @dev emit `EventCancelled` event
    function cancelEvent(uint _eventId)
        external
        nonReentrant
        storeOpen
        validEventId(_eventId)
        onlyOrganizer(_eventId)
    {
        require(events[_eventId].status == EventStatus.Created
            || events[_eventId].status == EventStatus.SalesFinished,
            "event must have just be created or have its ticket sales suspended in order to proceed");
        events[_eventId].status = EventStatus.Cancelled;
        emit EventCancelled(_eventId, events[_eventId].externalId, msg.sender);
    }

    /// @notice Purchase one or more tickets.
    /// @param _eventId event internal ID
    /// @param _quantity number of tickets being purchase at once. It has to be greater than zero and available
    /// @param _externalId purchase external ID (usually for correlation). Cannot be empty. Will be stored hashed
    /// @param _timestamp purchase date provided by organizer (UNIX epoch)
    /// @param _customerId ID of the customer provided during purchase. Cannot be empty. Will be store hashed
    /// @return Purchase internal ID.
    /// @dev emit `PurchaseCompleted` event
    function purchaseTickets(
        uint _eventId,
        uint _quantity,
        string calldata _externalId,
        uint _timestamp,
        string calldata _customerId
    )
        external
        payable
        nonReentrant
        storeOpen
        validEventId(_eventId)
        returns (uint _purchaseId)
    {
        require(events[_eventId].status == EventStatus.SalesStarted,
            "event ticket sales have to had started in order to proceed");
        require(!Address.isContract(msg.sender),
            "customer address must refer to an account (i.e. not a contract) in order to proceed");
        require(_quantity > 0,
            "quantity of tickets must be greater than zero in order to proceed");
        require(_quantity <= events[_eventId].ticketsLeft,
            "not enough tickets left for the quantity requested. please change quantity in order to proceed");
        require(bytes(_externalId).length != 0,
            "purchase external ID must not be empty in order to proceed");
        require(_timestamp > 0,
            "purchase date must be provided (not zero)");
        require(bytes(_customerId).length != 0,
            "customer ID cannot be empty in order to proceed");
        require(msg.value == SafeMath.mul(_quantity, events[_eventId].ticketPrice),
            "customer funds sent on transaction must be equal to purchase total in order to proceed");
        _purchaseId = Counter.next(store.counterPurchases);
        purchases[_purchaseId].status = PurchaseStatus.Completed;
        purchases[_purchaseId].eventId = _eventId;
        purchases[_purchaseId].quantity = _quantity;
        purchases[_purchaseId].externalId = keccak256(bytes(_externalId));
        purchases[_purchaseId].timestamp = _timestamp;
        purchases[_purchaseId].customer = msg.sender;
        purchases[_purchaseId].customerId = keccak256(bytes(_customerId));
        purchases[_purchaseId].total = SafeMath.mul(_quantity, events[_eventId].ticketPrice);
        events[_eventId].ticketsSold = SafeMath.add(events[_eventId].ticketsSold, _quantity);
        events[_eventId].ticketsLeft = SafeMath.sub(events[_eventId].ticketsLeft, _quantity);
        events[_eventId].eventBalance = SafeMath.add(events[_eventId].eventBalance, purchases[_purchaseId].total);
        customerPurchases[msg.sender].push(_purchaseId);
        emit PurchaseCompleted(_purchaseId, purchases[_purchaseId].externalId, msg.sender, _eventId);
        return (_purchaseId);
    }

    /// @notice Cancel a purchase.
    /// @notice Other IDs are required in order to avoid fraudulent cancellations.
    /// @param _purchaseId purchase internal ID
    /// @param _externalId purchase external ID which will be hashed and then compared to store one
    /// @param _customerId purchase customer ID which will be hashed and then compared to store one
    /// @dev emit `PurchaseCancelled` event
    function cancelPurchase(
        uint _purchaseId,
        string calldata _externalId,
        string calldata _customerId
    )
        external
        nonReentrant
        storeOpen
        validPurchaseId(_purchaseId)
        purchaseCompleted(_purchaseId)
    {
        uint _eventId = purchases[_purchaseId].eventId;
        require(events[_eventId].status == EventStatus.SalesStarted
            || events[_eventId].status == EventStatus.SalesSuspended
            || events[_eventId].status == EventStatus.SalesFinished
            || events[_eventId].status == EventStatus.Cancelled,
            "event status must allow cancellation in order to proceed");
        require(msg.sender == purchases[_purchaseId].customer,
            "purchase cancellation must be initiated by purchase customer in order to proceed");
        require(keccak256(bytes(_customerId)) == purchases[_purchaseId].customerId,
            "hashed customer ID must match with stored one in order to proceed");
        require(keccak256(bytes(_externalId)) == purchases[_purchaseId].externalId,
            "hashed purchase external ID must match with stored one in order to proceed");
        purchases[_purchaseId].status = PurchaseStatus.Cancelled;
        events[_eventId].ticketsCancelled = SafeMath.add(
            events[_eventId].ticketsCancelled,
            purchases[_purchaseId].quantity);
        events[_eventId].ticketsLeft = SafeMath.add(
            events[_eventId].ticketsLeft,
            purchases[_purchaseId].quantity);
        events[_eventId].eventBalance = SafeMath.sub(
            events[_eventId].eventBalance,
            purchases[_purchaseId].total);
        events[_eventId].refundableBalance = SafeMath.add(
            events[_eventId].refundableBalance,
            purchases[_purchaseId].total);
        store.refundable = SafeMath.add(
            store.refundable,
            purchases[_purchaseId].total);
        emit PurchaseCancelled(_purchaseId, purchases[_purchaseId].externalId, msg.sender, _eventId);
    }

    /// @notice Refund a cancelled purchase to customer.
    /// @param _eventId internal ID of the event associated to the purchase
    /// @param _purchaseId purchase internal ID
    /// @dev emit `PurchaseRefunded` event
    function refundPurchase(uint _eventId, uint _purchaseId)
        external
        nonReentrant
        storeOpen
        validEventId(_eventId)
        onlyOrganizer(_eventId)
        validPurchaseId(_purchaseId)
    {
        require(purchases[_purchaseId].status == PurchaseStatus.Cancelled,
            "ticket purchase have to be cancelled in order to proceed");
        purchases[_purchaseId].status = PurchaseStatus.Refunded;
        events[_eventId].ticketsRefunded = SafeMath.add(
            events[_eventId].ticketsRefunded,
            purchases[_purchaseId].quantity);
        events[_eventId].refundableBalance = SafeMath.sub(
            events[_eventId].refundableBalance,
            purchases[_purchaseId].total);
        store.refundable = SafeMath.sub(
            store.refundable,
            purchases[_purchaseId].total);
        purchases[_purchaseId].customer.transfer(purchases[_purchaseId].total);
        emit PurchaseRefunded(_purchaseId, purchases[_purchaseId].externalId, msg.sender, _eventId);
    }

    /// @notice Check into an event.
    /// @notice It means that customer and his/her companions (optional) attended to the event.
    /// @param _purchaseId purchase internal ID
    /// @dev emit `CustomerCheckedIn` event
    function checkIn(uint _purchaseId)
        external
        nonReentrant
        storeOpen
        validPurchaseId(_purchaseId)
        purchaseCompleted(_purchaseId)
    {
        uint _eventId = purchases[_purchaseId].eventId;
        require(events[_eventId].status == EventStatus.SalesStarted
            || events[_eventId].status == EventStatus.SalesSuspended
            || events[_eventId].status == EventStatus.SalesFinished,
            "event ticket sales should have been started/suspended/finished in order to proceed");
        require(msg.sender == purchases[_purchaseId].customer,
            "check-in request must be initiated from customer own account in order to proceed");
        purchases[_purchaseId].status = PurchaseStatus.CheckedIn;
        emit CustomerCheckedIn(_eventId, _purchaseId, msg.sender);
    }

    /// @notice Fetch store basic information.
    /// @notice Basic info are those static attributes set when store is created.
    /// @return Store attributes.
    function fetchStoreInfo()
        external
        view
        returns (
            address _owner,
            uint _status,
            string memory _name,
            uint _refundable,
            uint _counterEvents,
            uint _counterPurchases
        )
    {
        _owner = owner();
        _status = uint(store.status);
        _name = store.name;
        _refundable = store.refundable;
        _counterEvents = store.counterEvents.current;
        _counterPurchases = store.counterPurchases.current;
    }

    /// @notice Fetch event basic information.
    /// @notice Basic info are those static attributes set when event is created.
    /// @param _eventId event internal ID
    /// @return Event status, external ID, organizer address, event name, store incentive, ticket price and quantity of tickets for sale.
    function fetchEventInfo(uint _eventId)
        external
        view
        validEventId(_eventId)
        onlyOwnerOrOrganizer(_eventId)
        returns (
            uint _eventStatus,
            bytes32 _externalId,
            address _organizer,
            string memory _name,
            uint _storeIncentive,
            uint _ticketPrice,
            uint _ticketsOnSale
        )
    {
        _eventStatus = uint(events[_eventId].status);
        _externalId = events[_eventId].externalId;
        _organizer = events[_eventId].organizer;
        _name = events[_eventId].name;
        _storeIncentive = events[_eventId].storeIncentive;
        _ticketPrice = events[_eventId].ticketPrice;
        _ticketsOnSale = events[_eventId].ticketsOnSale;
    }

    /// @notice Fetch event sales information.
    /// @notice Sales info are those attributes which change upon each purchase/cancellation transaction.
    /// @param _eventId event internal ID
    /// @return Event status, tickets sold/left/cancelled/refunded/checked-in, event total/refundable balances.
    function fetchEventSalesInfo(uint _eventId)
        external
        view
        validEventId(_eventId)
        onlyOwnerOrOrganizer(_eventId)
        returns (
            uint _eventStatus,
            uint _ticketsSold,
            uint _ticketsLeft,
            uint _ticketsCancelled,
            uint _ticketsRefunded,
            uint _ticketsCheckedIn,
            uint _eventBalance,
            uint _refundableBalance
        )
    {
        _eventStatus = uint(events[_eventId].status);
        _ticketsSold = events[_eventId].ticketsSold;
        _ticketsLeft = events[_eventId].ticketsLeft;
        _ticketsCancelled = events[_eventId].ticketsCancelled;
        _ticketsRefunded = events[_eventId].ticketsRefunded;
        _ticketsCheckedIn = events[_eventId].ticketsCheckedIn;
        _eventBalance = events[_eventId].eventBalance;
        _refundableBalance = events[_eventId].refundableBalance;
    }

    /// @notice Fetch purchase information.
    /// @param _purchaseId purchase internal ID
    /// @return Purchase status, external ID, timestamp, customer address/ID, quantity of tickets, total and event ID.
    function fetchPurchaseInfo(uint _purchaseId)
        external
        view
        validPurchaseId(_purchaseId)
        returns (
            uint _purchaseStatus,
            bytes32 _externalId,
            uint _timestamp,
            address _customer,
            bytes32 _customerId,
            uint _quantity,
            uint _total,
            uint _eventId
        )
    {
        require(isOwner()
            || msg.sender == purchases[_purchaseId].customer
            || msg.sender == events[purchases[_purchaseId].eventId].organizer,
            "must be triggered by customer, event organizer or store owner in order to proceed");
        _purchaseStatus = uint(purchases[_purchaseId].status);
        _externalId = purchases[_purchaseId].externalId;
        _timestamp = purchases[_purchaseId].timestamp;
        _customer = purchases[_purchaseId].customer;
        _customerId = purchases[_purchaseId].customerId;
        _quantity = purchases[_purchaseId].quantity;
        _total = purchases[_purchaseId].total;
        _eventId = purchases[_purchaseId].eventId;
    }

    /// @notice Get number of events created by an organizer.
    /// @param _organizer organizer address
    /// @return Number of events. Zero in case organizer hasn't yet created any events.
    function getCountOrganizerEvents(address _organizer) 
        external
        view
        returns (uint)
    {
        require(msg.sender == owner() || msg.sender == _organizer,
            "not allowed to retrieve such information");
        return organizerEvents[_organizer].length;
    }

    /// @notice Get ID of an event, according to its position on list of events created by an organizer.
    /// @param _organizer organizer address
    /// @param _index position in the list. Starting from zero
    /// @return  Event ID
    function getEventIdByIndex(address _organizer, uint _index)
        external
        view
        returns (uint)
    {
        require(organizerEvents[_organizer].length != 0,
            "organizer has not created events yet");
        require(_index < organizerEvents[_organizer].length,
            "invalid index");
        return organizerEvents[_organizer][_index];
    }

    /// @notice Get number of ticket purchases performed by a customer.
    /// @param _customer customer address
    /// @return Number of purchases. Zero in case customer hasn't yet purchased any tickets.
    function getCountCustomerPurchases(address _customer) 
        external
        view
        returns (uint)
    {
        require(msg.sender == owner() || msg.sender == _customer,
            "not allowed to retrieve such information");
        return customerPurchases[_customer].length;
    }

    /// @notice Get ID of a purchase, according to its position on list of purchases performed by a customer.
    /// @param _customer customer address
    /// @param _index position in the list. Starting from zero
    /// @return Purchase ID
    function getPurchaseIdByIndex(address _customer, uint _index)
        external
        view
        returns (uint)
    {
        require(customerPurchases[_customer].length != 0,
            "customer has not purchased tickets yet");
        require(_index < customerPurchases[_customer].length,
            "invalid index");
        return customerPurchases[_customer][_index];
    }

}
