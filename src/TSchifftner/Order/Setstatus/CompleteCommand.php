<?php

namespace TSchifftner\Order\Setstatus;

use Mage;
use Mage_Sales_Model_Order;
use N98\Magento\Command\AbstractMagentoCommand;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

class CompleteCommand extends AbstractMagentoCommand
{
    const ORDER_STATUS = 'complete';

    protected function configure()
    {
        $this
          ->setName('order:setstatus:complete')
          ->addOption('increment-ids', null, InputOption::VALUE_OPTIONAL, 'Increment ids to select. Comma separated list with range (-) support. For example: 100004200-100004250,100003175,100000000-100000100,100000597')
          ->addOption('confirm-all', null, InputOption::VALUE_NONE, 'Confirm all by default')
          ->setDescription('Set complete status of orders')
        ;
    }

   /**
    * @param \Symfony\Component\Console\Input\InputInterface $input
    * @param \Symfony\Component\Console\Output\OutputInterface $output
    * @return int|void
    */
    protected function execute(InputInterface $input, OutputInterface $output)
    {
        $this->getApplication()->initMagento();

        /** @var Mage_Sales_Model_Resource_Order_Collection $orderCollection */
        $orderCollection = Mage::getResourceModel('sales/order_collection')
            ->addAttributeToFilter('status', array('nin' => array(
                Mage_Sales_Model_Order::STATE_COMPLETE,
                Mage_Sales_Model_Order::STATE_CANCELED,
                Mage_Sales_Model_Order::STATE_HOLDED,
            )));

        // filter order collection by increment ids
        if($input->getOption('increment-ids')) {
            $filter = array();
            $cliIncrementIds = explode(',', $input->getOption('increment-ids'));
            foreach( (array) $cliIncrementIds as $incrementId) {
                if(false !== strpos($incrementId, '-')) {
                    list($from, $to) = explode('-', $incrementId);
                    $filter[] = array('from' => $from, 'to' => $to);
                } else {
                    $filter[] = array('eq' => $incrementId);
                }
            }
            $orderCollection->addAttributeToFilter('increment_id', $filter);
        }

        // confirm action
        $orderCount = $orderCollection->count();

        if( ! $orderCount) {
            $output->writeln('<info>No orders found</info>');
            return;
        }

        // inform customer about status
        $output->writeln(sprintf("<info>There are %s orders found.</info>", $orderCollection->count()));

        // confirm all if not single confirmation requested
        $question = sprintf(
            "<question>Are you sure to set completion status for all %s orders without asking?</question> [<comment>n</comment>]",
            $orderCount
        );

        $dialog = $this->getHelper('dialog');
        $singleConfirmation = ! $input->getOption('confirm-all');

        if ( ! $singleConfirmation && ! $dialog->askConfirmation($output, $question, false)) {
            return;
        }

        // start applying status
        foreach($orderCollection as $order) {
            //$order = $this->_initOrder($incrementId);

            $question = sprintf("<question>Are you sure to set completion status for <comment>[%s]</comment>?</question> [<comment>n</comment>]", $order->getIncrementId());
            if($singleConfirmation && ! $dialog->askConfirmation($output, $question, false)) {
                continue;
            }

            $output->writeln(sprintf("<info>Order %s:</info>", $order->getIncrementId()));

            // create invoice
            $this->_createInvoice($order, $output);

            // create shipment
            $this->_createShipment($order, $output);

            $order->save();
            $output->writeln(sprintf("<info>Status set for %s.</info>", $order->getIncrementId()));
            $output->writeln('');
        }
    }

    /**
     * Create invoice to order
     *
     * @param Mage_Sales_Model_Order $order
     * @param OutputInterface $output
     */
    protected function _createInvoice(Mage_Sales_Model_Order $order, OutputInterface $output)
    {
        if($order->hasInvoices()) {
            $output->writeln('<info>Invoice already exists.</info>');
            return;
        }

        if( ! $order->canInvoice()) {
            $output->writeln('<error>Cannot create invoice.</error>');
            return;
        }

        /** @var \Mage_Sales_Model_Service_Order $serviceOrder */
        $serviceOrder = Mage::getModel('sales/service_order', $order);

        /** @var \Mage_Sales_Model_Order_Invoice $invoice */
        $invoice = $serviceOrder->prepareInvoice();

        if (!$invoice->getTotalQty()) {
            $output->writeln('<error>Cannot create an invoice without products.</error>');
            return;
        }

        $invoice->setRequestedCaptureCase(\Mage_Sales_Model_Order_Invoice::CAPTURE_OFFLINE);
        $invoice->register();

        $output->writeln('<info>Invoice created</info>');
    }

    /**
     * Create shipment to order
     *
     * @param Mage_Sales_Model_Order $order
     * @param OutputInterface $output
     */
    protected function _createShipment(Mage_Sales_Model_Order $order, OutputInterface $output)
    {
        if($order->hasShipments()) {
            $output->writeln('<info>Shipment already exists.</info>');
            return;
        }

        if( ! $order->canShip()) {
            $output->writeln('<error>Cannot create shipment.</error>');
            return;
        }

        /** @var \Mage_Sales_Model_Service_Order $serviceOrder */
        $serviceOrder = Mage::getModel('sales/service_order', $order);

        /** @var \Mage_Sales_Model_Order_Shipment $shipment */
        $shipment = $serviceOrder->prepareShipment();

        if (!$shipment->getTotalQty()) {
            $output->writeln('<error>Cannot create a shipment without products.</error>');
            return;
        }

        $shipment->register();
        $output->writeln('<info>Shipment created</info>');
    }
}
