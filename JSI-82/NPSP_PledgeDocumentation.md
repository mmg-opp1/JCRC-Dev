Github Repo for NPSP:
https://github.com/SalesforceFoundation/NPSP

Manage Pledges
Track and manage pledges for gifts with multiple payments.

Note
Note Watch the Nonprofit Salesforce How-To Series video: Manage Multiple Payments.
What is a Pledge?
In the nonprofit world, a pledge is a promise to donate a set amount of money in installments over a period of time. This article explains how to track your pledges with Opportunities and Payments.
Enter a Pledge and Expected Payments
Let's see how you can use Opportunities and Payments to set up that $400 pledge from your donor, with a total of four $100 payments scheduled every three months.
Write Off One or More Scheduled Payments
When donors pledge a certain amount and cannot keep the payment schedule, or are unable to send in one or more payments, you can write off (i.e. "cancel") the payments you're expecting so that you can keep accurate donation records.
What is a Pledge?
In the nonprofit world, a pledge is a promise to donate a set amount of money in installments over a period of time. This article explains how to track your pledges with Opportunities and Payments.

In the nonprofit world, a pledge is a promise to donate a set amount of money in installments over a period of time. With a pledge, you know the total amount of the gift from your donor, along with their payment schedule. For example, a donor agrees to pledge a total of $400 to your organization, paid in $100 installments every 3 months.

This article explains how to track your pledges with Opportunities and Payments. This is the way to go if your organization uses accrual accounting, where all income is recorded when it's pledged rather than when it's received.

For information on tracking pledges based on other accounting methods, see Recurring Donations versus Opportunity Payments (Legacy).

Enter a Pledge and Expected Payments
Let's see how you can use Opportunities and Payments to set up that $400 pledge from your donor, with a total of four $100 payments scheduled every three months.

Create an Opportunity for the total amount that the donor has pledged. In this example, $400. You can create a new Opportunity from the Opportunities tab or from a button on the Contact or Account record (recommended). When you do the latter, Salesforce automatically pre-populates the new Opportunity with related information.
Set the Stage field to Pledged (or any appropriate open stage).
Set the Close Date depending on your standard practices. For example, in our quarterly example, if the first donation comes in on 4/15/2019, we set the Close Date to 4/15/2019—the start of the pledge.
Save the Opportunity record.
On the new Opportunity record, click the Related tab, then scroll to the Payments section and click Schedule Payments.
Schedule Payments button on the Payments related list.
In the Create a Payment Schedule section:
Set the # of Payments fields to 4 (quarterly). By default, you can schedule up to 12 payments for a single donation.
Note
Note Depending on the needs of your organization, you can change the maximum number of payments from the NPSP Settings page (Donations | Payments | Maximum Payments).
Set the Date of First Payment to the starting date for your quarterly payments (the date when the first payment comes in).
Set the payment Interval Number to the amount of time between scheduled payments and the Period to the unit of time you want to use. For quarterly payments, the Number is 3 and the Period is Month.
Select Credit Card, Checks, or Cash as the default Payment Method depending on the mode of donation.
Schedule Payments for this Opportunity
Click Calculate Payments.
Salesforce creates an editable list of scheduled payments. For our quarterly donation example, the payment calculator will create 4 payments with the first payment scheduled on 4/15/2019, the second one scheduled three months later (the payment interval) on 7/15/2019, and so on. At this point, you can adjust the payment amounts and dates on the payment schedule. This is helpful, for example, when you know that the final payment will be a different amount, or if the one of the payments will come in on different date.

Payments to be created
Click Create Payments. On the Opportunity Related tab, the Payments related list shows the payment schedule.
Payments related list
When a payment comes in, click Edit from the drop-down to the right of the Payment in the list, select Paid, and then save your changes.
When the final payment comes in and the full donation amount has been paid, the Opportunity is automatically closed. Its Stage is set to the value selected in the Opportunity Stage for When Fully Paid field in NPSP Settings, under Donations | Payments.
Note
Note Occasionally, you may receive a Payment whose amount is more than what was originally scheduled. If a Payment is marked as paid, and it pushes the total amount of Payments over the Opportunity Amount, the Opportunity will automatically be closed. According to the example above, Elise Malloy made a $400 donation that was scheduled to be paid out in four Payments. She paid the first and second as planned, and was scheduled to make her third Payment of $100 on 10/15/19 and her fourth Payment of $100 on 1/15/20. Let's say that instead, Elise pays $250 on 10/15/19. The 10/15/19 Payment will be marked as Paid and, since this Payment pushes the Opportunity Amount over the original $400 donation, the Opportunity will automatically be closed.
Write Off One or More Scheduled Payments
When donors pledge a certain amount and cannot keep the payment schedule, or are unable to send in one or more payments, you can write off (i.e. "cancel") the payments you're expecting so that you can keep accurate donation records.

Search for the Opportunity that contains the payment you want to write off.
On the Opportunity record, click the Related tab, then click Edit to the right of the payment.
Select Written Off.
Click Save.
If, unfortunately, a donor discontinues their payments entirely, write off all of their scheduled future payments to keep your donation records accurate.

Search for the Opportunity that contains the payments you want to write off.
On the Related tab, scroll to the Payments related list.
Click Show more actions icon, then click Write Off Payments.
On the Write Off Remaining Balance page, look at the date in the Write Off Payments section. By default Salesforce shows you the current date, and will write off all remaining payments. If you want to choose a later date after which you want to write off payments, you can enter it.
Click Write Off Payments. Back on the Opportunity record, you'll see that Salesforce has automatically summed up the remaining unpaid payments and displayed them as a single unpaid write off.
Change the Opportunity Stage to Posted to close out the donation.


Collecting pledges in Salesforce NPSP
By: Sara Metheny
4 minutes
The term pledge can mean something different to every nonprofit organization. The majority of organizations equate pledges with a promised donations. This is contrasted with a recurring donation where there is no specific commitment.


For some, a pledge is a commitment to make a one-time gift and pay at a later date. Other organizations set up annual pledges for donors with installment payments throughout the year. Similarly, some organizations allow for longer-term pledges that are paid in installments over several years.

Each of these pledge types are dependent on how the organization handles its accounting and fundraising practices within their instance of Salesforce’s Nonprofit Success Pack (NPSP).

 

Nonprofits collect pledges in NPSP in a variety of ways
Things can get especially complicated around the competing needs of accounting and fundraising departments for calculating cash and accrual totals throughout the pledge process. The fundraising department may want to see donation totals increase only after each payment, while the accounting department may want to book the whole pledge revenue in the accounting period in which the pledge was made.

Luckily, NPSP allows for some flexibility around pledge models so that you can choose the system that works best for your organization. You have two main options for tracking pledges in NPSP.

 

Option #1: Use an accrual accounting method and the NPSP Payment object
The accrual accounting method for pledges in Salesforce NPSP

The first option is creating one Opportunity for the whole pledge amount and scheduling future payments with the Payment object. You’ll use this when your accounting and fundraising departments want the Opportunity to represent the full pledge amount and have it count towards a donor’s donation totals immediately. This is considered an ‘accrual’ model since the whole pledge amount will hit the donor’s gift totals when the opportunity is marked as closed-won.

In the accrual model, we're showing that the whole pledge amount hits the rollups at once, with the payments sitting below them and not affecting the rollups.

Pros of Option #1:

Good for pledges where the total donation amount is declared up front
Allows for solicitor credit for the whole pledge
Works with most payment processors
Cons of Option #1:

Not good for recurring donations where the roll-up amount for account/contact should increase with each paid payment
Can’t assign solicitor credit at the individual payment level
Can’t assign General Accounting Units (GAUs) allocation at the individual payment level
 

Option #2: Use a cash accounting method and the NPSP Recurring Donation object
The cash accounting method for pledges in Salesforce NPSP

The second option within NPSP is to use the Recurring Donation object (and optionally rename that object to ‘Pledge’) to log the pledge total, then each payment installment can be represented by an Opportunity. You’ll use this when your accounting and fundraising departments want each opportunity payment to increase the donor’s donation totals when payment is received. This model is considered a ‘cash’ model because each installment will increase the donor’s gift totals when it’s paid.

In the cash model, each opportunity represents a payment and will individually affect the rollups. The recurring donation record sits above those opportunity payments representing the whole pledge and not affecting the rollups.

Pros of Option #2:

Good for recurring donations where the total donation amount is not declared, only the installment amount
Allows for different General Accounting Units (GAUs) allocation for each payment
Allows for different solicitor credit for each payment
Cons of Option #2:

Difficult to handle an “end date” - have to use installment number, which is clunky
Not many payment processors will accommodate this model. (iATS Brickwork is the only known processor that can natively handle this.)
Can’t assign solicitor credit to the whole pledge/recurring donation, only the individual installments
The NPSP Recurring Donation object has some known bugs and limitations
 

Some organizations with more complex needs may need additional customization on top of these models. If you’re looking for more customization you should check out these five suggestions for extending NPSP from our friends at Soapbox Engage.

 

Integrating automatic payment solutions can also introduce more complexity. While NPSP is not an accounting platform, Salesforce can track various payment types. If you’re looking for a more in-depth view of how to track donations in NPSP, we suggest reading our article “Two options for tracking donations in NPSP”.