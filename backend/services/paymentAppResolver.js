const FULLPOS_PROTOCOL_URL = 'fullpos://payment/result';
const FULLCREDIT_PROTOCOL_URL = 'fullcredit://payment/result';

function paymentAppForOrder(order) {
  const projectCode = String(order?.project_code || '').trim().toUpperCase();
  if (projectCode === 'FULLCREDIT') {
    return {
      name: 'FullCredit',
      protocolUrl: FULLCREDIT_PROTOCOL_URL,
    };
  }
  return {
    name: 'FullPOS',
    protocolUrl: FULLPOS_PROTOCOL_URL,
  };
}

module.exports = {
  FULLPOS_PROTOCOL_URL,
  FULLCREDIT_PROTOCOL_URL,
  paymentAppForOrder,
};
