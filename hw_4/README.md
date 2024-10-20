# Notes

  # ImtOrder

  ImtOrder is a simple software that processes and orchestrates an order, from order
  place to delivery.
  It includes :
  - check and reservation in warehouse
  - payment
  - shipping and delivery

  But this software is not able to do everything. Some operations are processed by
  third parties :
  - Another software is responsible for stock management,
  - The payment are processed by a PSP (e.g. Paypal),
  - Deliveries are made by a specialized company with its own software (e.g. UPS)

  What this software does is managing the entire lifecycle of the order, while delegating
  some precise responsibilities to other systems.