pragma solidity ^0.4.25;

contract HPSGame {
    
    uint8 public constant Hammer = 1;
    uint8 public constant Papper = 2;
    uint8 public constant scissor = 3;
    
    uint8 private constant initState = 0;
    uint8 private constant addP1State = 1;
    uint8 private constant addP2State = 2;
    uint8 private constant reviewed1State = 3;
    uint8 private constant reviewed2State = 4;
    uint8 private constant ending = 5;
    
    struct player {
        address addr;
        uint256 amount;
        bytes32 answerHash;
    }
    
    struct challenge {
        player p1;
        player p2;
        uint8 state;
        uint64 expireTime;
        uint8 p1Ans;
        uint8 p2Ans;
    }
    
    uint256 public latestSlot = 0;
    
    mapping (uint256 => challenge) private challenges;
    
    event DrawGame(address,uint256,address,uint256);
    event Winner(address,uint256);
    
    modifier properStringSize(string s) {
        require(bytes(s).length <= 32);
        _;
    }
    
    modifier properTime(uint64 t) {
        require(t >= now + 1 minutes && t <= now + 1 days);
        _;
    }
    
    function viewSlot(uint256 _slot) public view returns(
        address,
        uint256,
        bytes32,
        address,
        uint256,
        bytes32,
        uint8,
        uint64,
        uint8,
        uint8
    ) {
        challenge storage tmp = challenges[_slot];
        return (
            tmp.p1.addr,
            tmp.p1.amount,
            tmp.p1.answerHash,
            tmp.p2.addr,
            tmp.p2.amount,
            tmp.p2.answerHash,
            tmp.state,
            tmp.expireTime,
            tmp.p1Ans,
            tmp.p2Ans
        );
    }
    
    function getNow() public view returns(uint64) {
        return uint64(now);
    }
    
    function getMinMaxExpireTime() public view returns(uint64,uint64) {
        return (uint64(now + 1 minutes),uint64(now + 1 days));
    }
    
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }
    
    function generateHash(string _salt, uint8 _answer)
    properStringSize(_salt)
    public pure returns(bytes32) {
        require(_answer > 0 && _answer < 4);
        return keccak256(_salt, _answer);
    }
    
    function createChallenge(uint256 _slot, uint64 _expireTime, bytes32 _answerHash) 
    properTime(_expireTime)
    public payable {
        require(_slot == latestSlot);
        require(msg.value > 0);
        require(challenges[latestSlot].state == initState);
        
        challenges[latestSlot] = challenge(
            player(msg.sender, msg.value, _answerHash),
            player(address(0),0,keccak256(0)),
            initState,
            _expireTime,
            0,
            0
        );
        
        challenges[latestSlot].state = addP1State;
        latestSlot++;
    }
    
    function joinChallenge(uint256 _slot, bytes32 _answerHash) public payable {
        require(challenges[_slot].state == addP1State);
        require(msg.value == challenges[_slot].p1.amount);
        
        challenges[_slot].p2.addr = msg.sender;
        challenges[_slot].p2.amount = msg.value;
        challenges[_slot].p2.answerHash = _answerHash;
        
        challenges[_slot].state = addP2State;
    }
    
    function reviewedAnswer(uint256 _slot, string _salt, uint8 _answer) public {
        require(_answer > 0 && _answer < 4);
        require(now <= challenges[_slot].expireTime);
        require(challenges[_slot].state == addP2State || challenges[_slot].state == reviewed1State);
        require(msg.sender == challenges[_slot].p1.addr || msg.sender == challenges[_slot].p2.addr);
        
        bytes32 _hash;
        if (msg.sender == challenges[_slot].p1.addr) {
            require(challenges[_slot].p1Ans == 0);
            _hash = challenges[_slot].p1.answerHash;
        } else {
            require(challenges[_slot].p2Ans == 0);
            _hash = challenges[_slot].p2.answerHash;
        }
        
        bytes32 reviewedHash = generateHash(_salt, _answer);
        
        require(reviewedHash == _hash);
        if (msg.sender == challenges[_slot].p1.addr) {
            challenges[_slot].p1Ans = _answer;
        } else {
            challenges[_slot].p2Ans = _answer;
        }
        
        if (challenges[_slot].state == addP2State) {
            challenges[_slot].state = reviewed1State;
        } else {
            challenges[_slot].state = reviewed2State;
        }
    }
    
    function finalizeGame(uint256 _slot) public payable {
        require(_slot < latestSlot);
        
        uint256 _amount = challenges[_slot].p1.amount + challenges[_slot].p2.amount;
        require(_amount > challenges[_slot].p1.amount && _amount > challenges[_slot].p2.amount);
        
        if (challenges[_slot].expireTime > now) {
            if (challenges[_slot].state == reviewed1State) {
                if (challenges[_slot].p1Ans > 0) {
                    challenges[_slot].p1.addr.transfer(_amount);
                    emit Winner(challenges[_slot].p1.addr,_amount);
                } else if (challenges[_slot].p2Ans > 0) {
                    challenges[_slot].p2.addr.transfer(_amount);
                    emit Winner(challenges[_slot].p2.addr,_amount);
                }
            } else {
                challenges[_slot].p1.addr.transfer(challenges[_slot].p1.amount);
                challenges[_slot].p2.addr.transfer(challenges[_slot].p2.amount);
                emit DrawGame(challenges[_slot].p1.addr,challenges[_slot].p1.amount,challenges[_slot].p2.addr,challenges[_slot].p2.amount);
            }
            
            challenges[_slot].state = ending;
        } else {
            require(challenges[_slot].state == addP2State);
            
            uint8 p2AnsMinus1 = (challenges[_slot].p2Ans > 1)? challenges[_slot].p2Ans - 1: 3;
            
            if (challenges[_slot].p1Ans == challenges[_slot].p2Ans) {
                challenges[_slot].p1.addr.transfer(challenges[_slot].p1.amount);
                challenges[_slot].p2.addr.transfer(challenges[_slot].p2.amount);
                emit DrawGame(challenges[_slot].p1.addr,challenges[_slot].p1.amount,challenges[_slot].p2.addr,challenges[_slot].p2.amount);
            } else if (challenges[_slot].p1Ans == p2AnsMinus1) {
                challenges[_slot].p1.addr.transfer(_amount);
                emit Winner(challenges[_slot].p1.addr,_amount);
            } else {
                challenges[_slot].p2.addr.transfer(_amount);
                emit Winner(challenges[_slot].p2.addr,_amount);
            }
            
            challenges[_slot].state = ending;
        }
    }
}
