;; carbon-tracker
;; A contract for tracking user carbon footprints and managing offset mechanisms on the Stacks blockchain
;; This contract allows users to record and track emissions-generating activities, calculate their total
;; carbon footprint, earn achievement badges, and purchase carbon offsets from verified projects.

;; ==================
;; Constants / Error Codes
;; ==================

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-ACTIVITY (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INVALID-CATEGORY (err u103))
(define-constant ERR-PROJECT-NOT-FOUND (err u104))
(define-constant ERR-INSUFFICIENT-CREDITS (err u105))
(define-constant ERR-INVALID-PROJECT (err u106))
(define-constant ERR-BADGE-ALREADY-AWARDED (err u107))
(define-constant ERR-BADGE-NOT-FOUND (err u108))

;; Activity categories
(define-constant CATEGORY-TRANSPORTATION u1)
(define-constant CATEGORY-ENERGY u2)
(define-constant CATEGORY-FOOD u3)
(define-constant CATEGORY-GOODS u4)
(define-constant CATEGORY-SERVICES u5)

;; ==================
;; Data Maps and Variables
;; ==================

;; Stores the total carbon footprint for each user (in kg CO2e)
(define-map user-footprints principal uint)

;; Tracks individual carbon-emitting activities recorded by users
(define-map user-activities { user: principal, activity-id: uint } 
  { 
    category: uint,
    timestamp: uint,
    amount: uint,
    description: (string-ascii 100),
    carbon-value: uint
  }
)

;; Keeps count of activities per user for generating new activity IDs
(define-map user-activity-count principal uint)

;; Tracks carbon offsets/credits owned by users (in kg CO2e)
(define-map user-offsets principal uint)

;; Stores information about sustainability projects that offer carbon offsets
(define-map offset-projects uint
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    price-per-ton: uint,  ;; Price in microSTX per ton of carbon offset
    available-credits: uint,  ;; Available carbon credits in kg CO2e
    verified: bool,
    owner: principal
  }
)

;; Tracks the next project ID to be assigned
(define-data-var next-project-id uint u1)

;; Maps achievement badges to users
(define-map user-badges { user: principal, badge-id: uint } bool)

;; Badge definitions
(define-map badges uint
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    requirement-type: (string-ascii 20),  ;; "reduction", "offset", "activity", etc.
    requirement-value: uint
  }
)

;; ==================
;; Private Functions
;; ==================

;; Calculate carbon value for a transportation activity
;; Returns carbon value in kg CO2e
(define-private (calculate-transportation-carbon (distance uint) (mode (string-ascii 20)))
  (if (is-eq mode "car")
      ;; Approximate emissions for car: 0.2 kg CO2e per km
      (* distance u200)
      (if (is-eq mode "bus")
          ;; Approximate emissions for bus: 0.1 kg CO2e per km
          (* distance u100)
          (if (is-eq mode "train")
              ;; Approximate emissions for train: 0.05 kg CO2e per km
              (* distance u50)
              ;; Default value if mode not recognized
              (* distance u200)))))

;; Helper to get user's current footprint, returns 0 if not found
(define-private (get-user-footprint (user principal))
  (default-to u0 (map-get? user-footprints user)))

;; Helper to get user's current offset credits, returns 0 if not found
(define-private (get-user-offsets (user principal))
  (default-to u0 (map-get? user-offsets user)))

;; Helper to get user's activity count, returns 0 if not found
(define-private (get-user-activity-count (user principal))
  (default-to u0 (map-get? user-activity-count user)))

;; Check if a category is valid
(define-private (is-valid-category (category uint))
  (or
    (is-eq category CATEGORY-TRANSPORTATION)
    (is-eq category CATEGORY-ENERGY)
    (is-eq category CATEGORY-FOOD)
    (is-eq category CATEGORY-GOODS)
    (is-eq category CATEGORY-SERVICES)))

;; Update a user's footprint with a new carbon value
(define-private (update-user-footprint (user principal) (carbon-value uint))
  (let ((current-footprint (get-user-footprint user)))
    (map-set user-footprints user (+ current-footprint carbon-value))
    (ok carbon-value)))

;; Check if a user qualifies for any new badges
(define-private (check-badges (user principal))
  (let ((footprint (get-user-footprint user))
        (offsets (get-user-offsets user)))
    ;; Implementation would check various badge conditions
    ;; This is a simplified placeholder
    (ok true)))

;; ==================
;; Read-Only Functions
;; ==================

;; Get a user's total carbon footprint
(define-read-only (get-footprint (user principal))
  (ok (get-user-footprint user)))

;; Get a user's net carbon impact (footprint minus offsets)
(define-read-only (get-net-carbon-impact (user principal))
  (let ((footprint (get-user-footprint user))
        (offsets (get-user-offsets user)))
    (ok (- footprint offsets))))

;; Get details of a specific activity
(define-read-only (get-activity (user principal) (activity-id uint))
  (map-get? user-activities { user: user, activity-id: activity-id }))

;; Get details of an offset project
(define-read-only (get-project (project-id uint))
  (map-get? offset-projects project-id))

;; Get user's offset credits
(define-read-only (get-offset-credits (user principal))
  (ok (get-user-offsets user)))

;; Check if user has a specific badge
(define-read-only (has-badge (user principal) (badge-id uint))
  (default-to false (map-get? user-badges { user: user, badge-id: badge-id })))

;; Get details of a badge
(define-read-only (get-badge-details (badge-id uint))
  (map-get? badges badge-id))

;; ==================
;; Public Functions
;; ==================

;; Record a new carbon-emitting activity
(define-public (record-activity (category uint) (amount uint) (description (string-ascii 100)) (carbon-value uint))
  (let ((user tx-sender)
        (activity-count (get-user-activity-count user)))
    
    ;; Verify the category is valid
    (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
    
    ;; Verify amount is positive
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Store the activity
    (map-set user-activities 
      { user: user, activity-id: activity-count }
      { 
        category: category, 
        timestamp: block-height, 
        amount: amount, 
        description: description,
        carbon-value: carbon-value
      }
    )
    
    ;; Increment the activity counter for this user
    (map-set user-activity-count user (+ activity-count u1))
    
    ;; Update the user's total footprint
    (update-user-footprint user carbon-value)
    
    ;; Check if this activity qualifies the user for any badges
    (check-badges user)
    
    (ok activity-count)))

;; Simplified transportation activity recording with automatic carbon calculation
(define-public (record-transportation (distance uint) (mode (string-ascii 20)) (description (string-ascii 100)))
  (let ((carbon-value (calculate-transportation-carbon distance mode)))
    (record-activity CATEGORY-TRANSPORTATION distance description carbon-value)))

;; Register a new offset project
(define-public (register-offset-project (name (string-ascii 100)) 
                                         (description (string-ascii 500))
                                         (price-per-ton uint)
                                         (initial-credits uint))
  (let ((project-id (var-get next-project-id))
        (owner tx-sender))
    
    ;; Ensure price and credits are reasonable
    (asserts! (> price-per-ton u0) ERR-INVALID-AMOUNT)
    (asserts! (> initial-credits u0) ERR-INVALID-AMOUNT)
    
    ;; Create the project
    (map-set offset-projects project-id
      {
        name: name,
        description: description,
        price-per-ton: price-per-ton,
        available-credits: initial-credits,
        verified: false,  ;; Projects start unverified
        owner: owner
      }
    )
    
    ;; Increment project ID for next time
    (var-set next-project-id (+ project-id u1))
    
    (ok project-id)))

;; Verify a project (would typically be restricted to contract owner or designated verifiers)
(define-public (verify-project (project-id uint))
  (let ((project (unwrap! (map-get? offset-projects project-id) ERR-PROJECT-NOT-FOUND)))
    ;; In a real implementation, this would check tx-sender against authorized verifiers
    ;; For simplicity, we're allowing any caller (this should be restricted in production)
    
    ;; Update the project to verified status
    (map-set offset-projects project-id
      (merge project { verified: true })
    )
    
    (ok true)))

;; Purchase carbon offsets from a project
(define-public (purchase-offset (project-id uint) (amount uint))
  (let ((user tx-sender)
        (project (unwrap! (map-get? offset-projects project-id) ERR-PROJECT-NOT-FOUND))
        (price-in-ustx (/ (* amount (get price-per-ton project)) u1000)))  ;; Convert kg to tons (1000 kg)
    
    ;; Check if project is verified
    (asserts! (get verified project) ERR-INVALID-PROJECT)
    
    ;; Check if enough credits are available
    (asserts! (>= (get available-credits project) amount) ERR-INSUFFICIENT-CREDITS)
    
    ;; Transfer STX from user to project owner
    (try! (stx-transfer? price-in-ustx user (get owner project)))
    
    ;; Update project's available credits
    (map-set offset-projects project-id
      (merge project { available-credits: (- (get available-credits project) amount) })
    )
    
    ;; Update user's offset balance
    (let ((current-offsets (get-user-offsets user)))
      (map-set user-offsets user (+ current-offsets amount))
    )
    
    ;; Check if this purchase qualifies the user for any badges
    (check-badges user)
    
    (ok amount)))

;; Award a badge to a user
;; In a production app, this would typically be restricted to administrators or automated
(define-public (award-badge (user principal) (badge-id uint))
  (let ((badge (unwrap! (map-get? badges badge-id) ERR-BADGE-NOT-FOUND)))
    
    ;; Check if user already has this badge
    (asserts! (not (has-badge user badge-id)) ERR-BADGE-ALREADY-AWARDED)
    
    ;; Award the badge
    (map-set user-badges { user: user, badge-id: badge-id } true)
    
    (ok true)))

;; Initialize a badge
(define-public (initialize-badge (badge-id uint) 
                                 (name (string-ascii 50)) 
                                 (description (string-ascii 200))
                                 (requirement-type (string-ascii 20))
                                 (requirement-value uint))
  ;; In a production app, this would be restricted to administrators
  (map-set badges badge-id
    {
      name: name,
      description: description,
      requirement-type: requirement-type,
      requirement-value: requirement-value
    }
  )
  (ok true))