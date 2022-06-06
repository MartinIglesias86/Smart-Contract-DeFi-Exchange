//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Exchange is ERC20 {
    address public cryptoDevTokenAddress;

    //Exchange is inheriting ERC20, because our exchange would keep track of Crypto Dev LP tokens
    constructor(address _CryptoDevtoken) ERC20("CryptoDev LP Token", "CDLP") {
        require(_CryptoDevtoken != address(0), "La direccion del token no puede ser nula");
        cryptoDevTokenAddress = _CryptoDevtoken;
    }

    //@dev getReserve returns the amount of 'Crypto Dev Tokens' held by the contract
    function getReserve() public view returns (uint) {
        return ERC20(cryptoDevTokenAddress).balanceOf(address(this));
    }

    //@dev addLiquidity adds liquidity to the exchange
    function addLiquidity(uint _amount) public payable returns (uint) {
        uint liquidity;
        uint ethBalance = address(this).balance;
        uint cryptoDevTokenReserve = getReserve();
        ERC20 cryptoDevToken = ERC20(cryptoDevTokenAddress);
        
        //If the reserve is empty, intake any user supplied value for 'Ether' and 'Crypto Dev' tokens because there is no ratio currently
        if(cryptoDevTokenReserve == 0) {
            //transfer the 'cryptoDevToken' from the user's account to the contract
            cryptoDevToken.transferFrom(msg.sender, address(this), _amount);
            /*
            Take the current ethBalance and mint 'ethBalance' amount of LP tokens to the user.
            'liquidity' provided is equal to 'ethBalance' because this is the first time the user is adding 'Eth' to the contract,
            so whathever 'Eth' contract has is equal to the one supplied by the user in the current 'addLiquidity' call.
            'liquidity' tokens that need to be minted to the user on 'addLiquidity' call should always be proportional to the Eth 
            specified by the user.
            */
            liquidity = ethBalance;
            //_mint is ERC20.sol smart contract function to mint ERC20 tokens
            _mint(msg.sender, liquidity);
        } else {
            /*
            If the reserve is not empty, intake any user supplied value for 'Ether' and determine according to the ratio how many
            'Crypto Dev' tokens need to be supplied to prevent any large price impacts because of the additional liquidity.
            */
            //ethReserve should be the current ethBalance substracted by the value of ether sent by the user in the current 'addLiquidity' call
            uint ethReserve = ethBalance - msg.value;
            /*
            The ratio should always be maintained so that are no major price impacts when adding liquidity.
            Ratio here is -> (cryptoDevTokenAmount user can add/cryptoDevTokenReserve in the contract) = (Eth sent by the user/Eth reserve in the contract).
            So doing some maths, (cryptoDevTokenAmount user can add) = (Eth sent by the user * cryptoDevTokenReserve / Eth reserve)
            */
            uint cryptoDevTokenAmount = (msg.value * cryptoDevTokenReserve) / ethReserve;
            require(_amount >= cryptoDevTokenAmount, "La cantidad de tokens enviados es menor que los tokens minimos requeridos");
            //transfer only (cryptoDevTokenAmount user can add) amount of 'Crypto Dev tokens' from users account to the contract
            cryptoDevToken.transferFrom(msg.sender, address(this), cryptoDevTokenAmount);
            /*
            The amount of LP tokens that would be sent to the user should be proportional to the liquidity of ether added by the user.
            Ratio here to me maintained is -> 
            (LP tokens to be sent to the user (liquidity)/ totalSupply of LP tokens in contract) = (Eth sent by the user)/(Eth reserve in the contract).
            Doing some maths -> liquidity =  (totalSupply of LP tokens in contract * (Eth sent by the user))/(Eth reserve in the contract)
            */
            liquidity = (totalSupply() * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);
        }
        return liquidity;
    }

    //@dev removeLiquidity returns the amount of Eth/Crypto Dev tokens that would be returned
    //to the user in the swap
    function removeLiquidity(uint _amount) public returns (uint, uint) {
        require(_amount > 0, "la cantidad de tokens a retirar debe ser mayor a 0");
        uint ethReserve = address(this).balance;
        uint _totalSupply = totalSupply();
        /*
        The amount of Eth that would be sent back to the user is based on a ratio.
        The ratio is -> (Eth sent to the user) / (current Eth reserve) = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        then, by some maths -> (Eth sent back to the user) = (current Eth reserve * amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        */
        uint ethAmount = (ethReserve * _amount) / _totalSupply;
        /*
        The amount of Crypto Dev tokens that would be sent back to the user is based on a ratio.
        The ratio is -> (Crypto Dev tokens sent to the user) / (current Crypto Dev reserve) = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        then, by some maths -> (Crypto Dev tokens sent back to the user) = (current Crypto Dev reserve * amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        */
        uint cryptoDevTokenAmount = (getReserve() * _amount) / _totalSupply;
        //Burn the sent LP tokens from the user's wallet because they are already sent to remove liquidity
        _burn(msg.sender, _amount);
        //transfer 'ethAmount' of Eth from user's wallet to the contract
        payable(msg.sender).transfer(ethAmount);
        //transfer 'cryptoDevTokenAmount' of Crypto Dev tokens from user's wallet to the contract
        ERC20(cryptoDevTokenAddress).transfer(msg.sender, cryptoDevTokenAmount);
        return (ethAmount, cryptoDevTokenAmount);
    }

    //@dev getAmountOfTokens returns the amount of Eth/Crypto Dev tokens that would be returned to the user in the swap
    function getAmountOfTokens(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Reservas invalidas. Los valores deben ser mayores a 0");
        //we are charging a fee of '1%'
        //input amount with fee = (input amount - (1*(input amount)/100)) = ((input amount)*99)/100
        uint256 inputAmountWithFee = inputAmount * 99;
        /*
        Because we need to follow the concepto of 'XY=K' curve we need to make sure that (x + Δx) * (y - Δy) = x * y
        so the final formula is Δy = (y * Δx) / (x + Δx).
        Δy in our case is 'tokens to be received'
        Δx = ((input amount)*99)/100, x = inputReserve, y = outputReserve
        So by putting the values in the formula you can get the numerator and denominator
        */
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;
        return numerator / denominator;
    }

    //@dev ethToCryptoDevToken swaps Eth for CryptoDev Tokens
    function ethToCryptoDevToken(uint _minTokens) public payable {
        uint256 tokenReserve = getReserve();
        /*
        Call the 'getAmountOfTokens' to get the amount of Crypto Dev tokens that would be returned to the user after the swap.
        Notice that the 'inputReserve' we are sending is equal to `address(this).balance - msg.value` instead of just `address(this).balance`
        because 'address(this).balance' already contains the 'msg.value' the user has sent in the given call so we need to substract it
        to get the actual input reserve.
        */
        uint256 tokensBought = getAmountOfTokens(
            msg.value,
            address(this).balance - msg.value,
            tokenReserve
        );
        require(tokensBought >= _minTokens, "Cantidad a retirar insuficiente");
        //transfer the 'Crypto Dev' tokens to the user
        ERC20(cryptoDevTokenAddress).transfer(msg.sender, tokensBought);
    }

    //@dev cryptoDevTokenToEth swaps CryptoDev Tokens for Eth
    function cryptoDevTokenToEth(uint _tokensSold, uint _minEth) public {
        uint256 tokenReserve = getReserve();
        //call the 'getAmountOfTokens' to get the amount of Eth that would be returned to the user after the swap
        uint256 ethBought = getAmountOfTokens(
            _tokensSold,
            tokenReserve,
            address(this).balance
        );
        require(ethBought >= _minEth, "Cantidad a retirar insuficiente");
        //transfer 'CryptoDev' tokens from the user's address to the contract
        ERC20(cryptoDevTokenAddress).transferFrom(msg.sender, address(this), _tokensSold);
        //send the 'ethBought' to the user from the contract
        payable(msg.sender).transfer(ethBought);
    }
}
