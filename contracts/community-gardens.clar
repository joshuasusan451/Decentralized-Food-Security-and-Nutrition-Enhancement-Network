;; Community Garden Coordination Contract
;; Organizes and supports local food production initiatives

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-ALREADY-EXISTS (err u201))
(define-constant ERR-NOT-FOUND (err u202))
(define-constant ERR-INVALID-INPUT (err u203))
(define-constant ERR-PLOT-OCCUPIED (err u204))
(define-constant ERR-NOT-PLOT-HOLDER (err u205))

;; Data Variables
(define-data-var next-garden-id uint u1)
(define-data-var next-plot-id uint u1)

;; Data Maps
(define-map gardens
  { garden-id: uint }
  {
    name: (string-ascii 100),
    location: (string-ascii 200),
    total-plots: uint,
    available-plots: uint,
    coordinator: principal,
    created-at: uint,
    active: bool
  }
)

(define-map garden-plots
  { plot-id: uint }
  {
    garden-id: uint,
    plot-number: uint,
    holder: (optional principal),
    assigned-at: (optional uint),
    size-sqft: uint,
    plot-type: (string-ascii 50) ;; "vegetable", "herb", "fruit", "mixed"
  }
)

(define-map harvest-records
  { plot-id: uint, harvest-date: uint }
  {
    crop-type: (string-ascii 50),
    quantity-lbs: uint,
    distributed-to-community: uint,
    notes: (string-ascii 300)
  }
)

(define-map volunteer-hours
  { garden-id: uint, volunteer: principal, date: uint }
  {
    hours: uint,
    activity: (string-ascii 100),
    verified: bool
  }
)

(define-map garden-coordinators
  { coordinator: principal }
  { authorized: bool }
)

;; Authorization Functions
(define-public (authorize-coordinator (coordinator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set garden-coordinators { coordinator: coordinator } { authorized: true }))
  )
)

;; Garden Management Functions
(define-public (create-garden (name (string-ascii 100)) (location (string-ascii 200)) (total-plots uint) (coordinator principal))
  (let
    (
      (garden-id (var-get next-garden-id))
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len location) u0) ERR-INVALID-INPUT)
    (asserts! (> total-plots u0) ERR-INVALID-INPUT)

    (map-set gardens
      { garden-id: garden-id }
      {
        name: name,
        location: location,
        total-plots: total-plots,
        available-plots: total-plots,
        coordinator: coordinator,
        created-at: block-height,
        active: true
      }
    )
    (map-set garden-coordinators { coordinator: coordinator } { authorized: true })
    (var-set next-garden-id (+ garden-id u1))
    (ok garden-id)
  )
)

(define-public (add-plot (garden-id uint) (size-sqft uint) (plot-type (string-ascii 50)))
  (let
    (
      (garden (unwrap! (map-get? gardens { garden-id: garden-id }) ERR-NOT-FOUND))
      (plot-id (var-get next-plot-id))
      (plot-number (+ (get total-plots garden) u1))
    )
    (asserts! (is-eq tx-sender (get coordinator garden)) ERR-NOT-AUTHORIZED)
    (asserts! (> size-sqft u0) ERR-INVALID-INPUT)
    (asserts! (> (len plot-type) u0) ERR-INVALID-INPUT)

    (map-set garden-plots
      { plot-id: plot-id }
      {
        garden-id: garden-id,
        plot-number: plot-number,
        holder: none,
        assigned-at: none,
        size-sqft: size-sqft,
        plot-type: plot-type
      }
    )

    (map-set gardens
      { garden-id: garden-id }
      (merge garden {
        total-plots: plot-number,
        available-plots: (+ (get available-plots garden) u1)
      })
    )

    (var-set next-plot-id (+ plot-id u1))
    (ok plot-id)
  )
)

(define-public (assign-plot (plot-id uint) (new-holder principal))
  (let
    (
      (plot (unwrap! (map-get? garden-plots { plot-id: plot-id }) ERR-NOT-FOUND))
      (garden (unwrap! (map-get? gardens { garden-id: (get garden-id plot) }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get coordinator garden)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (get holder plot)) ERR-PLOT-OCCUPIED)

    (map-set garden-plots
      { plot-id: plot-id }
      (merge plot {
        holder: (some new-holder),
        assigned-at: (some block-height)
      })
    )

    (map-set gardens
      { garden-id: (get garden-id plot) }
      (merge garden {
        available-plots: (- (get available-plots garden) u1)
      })
    )
    (ok true)
  )
)

(define-public (release-plot (plot-id uint))
  (let
    (
      (plot (unwrap! (map-get? garden-plots { plot-id: plot-id }) ERR-NOT-FOUND))
      (garden (unwrap! (map-get? gardens { garden-id: (get garden-id plot) }) ERR-NOT-FOUND))
    )
    (asserts!
      (or
        (is-eq tx-sender (get coordinator garden))
        (is-eq (some tx-sender) (get holder plot))
      )
      ERR-NOT-AUTHORIZED
    )
    (asserts! (is-some (get holder plot)) ERR-NOT-FOUND)

    (map-set garden-plots
      { plot-id: plot-id }
      (merge plot {
        holder: none,
        assigned-at: none
      })
    )

    (map-set gardens
      { garden-id: (get garden-id plot) }
      (merge garden {
        available-plots: (+ (get available-plots garden) u1)
      })
    )
    (ok true)
  )
)

;; Harvest Tracking Functions
(define-public (record-harvest (plot-id uint) (crop-type (string-ascii 50)) (quantity-lbs uint) (distributed-to-community uint) (notes (string-ascii 300)))
  (let
    (
      (plot (unwrap! (map-get? garden-plots { plot-id: plot-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq (some tx-sender) (get holder plot)) ERR-NOT-PLOT-HOLDER)
    (asserts! (> (len crop-type) u0) ERR-INVALID-INPUT)
    (asserts! (> quantity-lbs u0) ERR-INVALID-INPUT)
    (asserts! (<= distributed-to-community quantity-lbs) ERR-INVALID-INPUT)

    (map-set harvest-records
      { plot-id: plot-id, harvest-date: block-height }
      {
        crop-type: crop-type,
        quantity-lbs: quantity-lbs,
        distributed-to-community: distributed-to-community,
        notes: notes
      }
    )
    (ok true)
  )
)

;; Volunteer Management Functions
(define-public (log-volunteer-hours (garden-id uint) (volunteer principal) (hours uint) (activity (string-ascii 100)))
  (let
    (
      (garden (unwrap! (map-get? gardens { garden-id: garden-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get coordinator garden)) ERR-NOT-AUTHORIZED)
    (asserts! (> hours u0) ERR-INVALID-INPUT)
    (asserts! (> (len activity) u0) ERR-INVALID-INPUT)

    (map-set volunteer-hours
      { garden-id: garden-id, volunteer: volunteer, date: block-height }
      {
        hours: hours,
        activity: activity,
        verified: true
      }
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-garden (garden-id uint))
  (map-get? gardens { garden-id: garden-id })
)

(define-read-only (get-plot (plot-id uint))
  (map-get? garden-plots { plot-id: plot-id })
)

(define-read-only (get-harvest-record (plot-id uint) (harvest-date uint))
  (map-get? harvest-records { plot-id: plot-id, harvest-date: harvest-date })
)

(define-read-only (get-volunteer-hours (garden-id uint) (volunteer principal) (date uint))
  (map-get? volunteer-hours { garden-id: garden-id, volunteer: volunteer, date: date })
)

(define-read-only (is-coordinator (coordinator principal))
  (default-to false (get authorized (map-get? garden-coordinators { coordinator: coordinator })))
)

(define-read-only (get-next-garden-id)
  (var-get next-garden-id)
)

(define-read-only (get-next-plot-id)
  (var-get next-plot-id)
)
