class OrdersController < ApplicationController

  def show
    @order = Order.includes(:line_items).find(params[:id])
  end

  def create
    charge = perform_stripe_charge
    @order  = create_order(charge)
    @user = current_user

    if @order.valid?
      empty_cart!
      UserMailer.order_placed_email(@order, @user).deliver_now unless current_user.nil?
      redirect_to @order
    else
      redirect_to cart_path, flash: { error: @order.errors.full_messages.first }
    end

  rescue Stripe::CardError => e
    redirect_to cart_path, flash: { error: e.message }
  end

  private

  def empty_cart!
    # empty hash means no products in cart :)
    update_cart({})
  end

  def perform_stripe_charge
    Stripe::Charge.create(
      source:      params[:stripeToken],
      amount:      cart_subtotal_cents,
      description: "Pascal's Jungle Order",
      currency:    'cad'
    )
  end

  def create_order(stripe_charge)
    @email ||= current_user&.email

    order = Order.new(
      email: @email,
      total_cents: cart_subtotal_cents,
      stripe_charge_id: stripe_charge.id, # returned by stripe
    )

    enhanced_cart.each do |entry|
      product = entry[:product]
      quantity = entry[:quantity]
      order.line_items.new(
        product: product,
        quantity: quantity,
        item_price: product.price,
        total_price: product.price * quantity
      )
    end
    order.save!
    order
  end

end
